CREATE TABLE moneda (
    codigo_iso  CHAR(3)      PRIMARY KEY,               -- COP, USD, EUR...
    nombre      VARCHAR(60)  NOT NULL,
    soportada   BOOLEAN      NOT NULL DEFAULT TRUE,     -- HU-01 esc.3
    CONSTRAINT ck_moneda_iso CHECK (codigo_iso = UPPER(codigo_iso))
);

CREATE TABLE tipo_cuenta (
    id_tipo_cuenta SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre         VARCHAR(30) NOT NULL UNIQUE          -- ahorros | corriente
);

CREATE TABLE perfil (                                    -- HU-04, HU-10, HU-12
    id_perfil                SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre                   VARCHAR(40)   NOT NULL UNIQUE,
    puntaje_crediticio_min   INTEGER       NOT NULL DEFAULT 0 CHECK (puntaje_crediticio_min >= 0),
    limite_diario_transf_intl NUMERIC(18,2) NOT NULL CHECK (limite_diario_transf_intl >= 0),
    monto_max_prestamo       NUMERIC(18,2) NOT NULL CHECK (monto_max_prestamo >= 0)
);

CREATE TABLE beneficio (                                 -- HU-12
    id_beneficio  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descripcion   VARCHAR(300) NOT NULL,
    vigente_desde DATE NOT NULL,
    vigente_hasta DATE,
    CONSTRAINT ck_beneficio_vigencia CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);

CREATE TABLE perfil_beneficio (
    id_perfil    SMALLINT NOT NULL REFERENCES perfil(id_perfil)       ON DELETE CASCADE,
    id_beneficio INTEGER  NOT NULL REFERENCES beneficio(id_beneficio) ON DELETE CASCADE,
    PRIMARY KEY (id_perfil, id_beneficio)
);

CREATE TABLE tipo_cuenta_beneficio (
    id_tipo_cuenta SMALLINT NOT NULL REFERENCES tipo_cuenta(id_tipo_cuenta) ON DELETE CASCADE,
    id_beneficio   INTEGER  NOT NULL REFERENCES beneficio(id_beneficio)     ON DELETE CASCADE,
    PRIMARY KEY (id_tipo_cuenta, id_beneficio)
);

-- =====================================================================
-- 2. PERSONAS
-- =====================================================================

CREATE TABLE empleado (                                  -- asesor | administrador
    id_empleado INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(120) NOT NULL,
    email       VARCHAR(150) NOT NULL UNIQUE,
    rol         VARCHAR(15)  NOT NULL CHECK (rol IN ('asesor','administrador')),
    activo      BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE cliente (
    id_cliente         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_documento     VARCHAR(20)  NOT NULL,
    num_identificacion VARCHAR(30)  NOT NULL,
    nombres            VARCHAR(100) NOT NULL,
    apellidos          VARCHAR(100) NOT NULL,
    fecha_nacimiento   DATE         NOT NULL CHECK (fecha_nacimiento <= CURRENT_DATE),
    pais_residencia    VARCHAR(60)  NOT NULL,
    email              VARCHAR(150) NOT NULL UNIQUE,
    telefono           VARCHAR(30),
    estado             VARCHAR(15)  NOT NULL DEFAULT 'activo'
                       CHECK (estado IN ('activo','inactivo','bloqueado')),
    id_perfil          SMALLINT     NOT NULL REFERENCES perfil(id_perfil),
    id_asesor          INTEGER      REFERENCES empleado(id_empleado),   -- HU-13
    fecha_registro     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, num_identificacion)
);

CREATE TABLE documento (                                 -- HU-01 esc.2
    id_documento      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente        INTEGER      NOT NULL REFERENCES cliente(id_cliente) ON DELETE CASCADE,
    tipo              VARCHAR(40)  NOT NULL,             -- identidad, comprobante de domicilio...
    archivo           VARCHAR(300) NOT NULL,
    fecha_carga       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    estado_validacion VARCHAR(12)  NOT NULL DEFAULT 'pendiente'
                      CHECK (estado_validacion IN ('pendiente','valido','rechazado'))
);

-- =====================================================================
-- 3. TASAS (HU-04, HU-15)
-- =====================================================================

CREATE TABLE tasa_cambio (
    id_tasa_cambio   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    moneda_origen    CHAR(3)       NOT NULL REFERENCES moneda(codigo_iso),
    moneda_destino   CHAR(3)       NOT NULL REFERENCES moneda(codigo_iso),
    valor            NUMERIC(18,8) NOT NULL CHECK (valor > 0),
    vigente_desde    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    vigente_hasta    TIMESTAMPTZ,
    id_administrador INTEGER       NOT NULL REFERENCES empleado(id_empleado),
    CONSTRAINT ck_tasa_cambio_monedas CHECK (moneda_origen <> moneda_destino),
    CONSTRAINT ck_tasa_cambio_vigencia CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde),
    CONSTRAINT uq_tasa_cambio UNIQUE (moneda_origen, moneda_destino, vigente_desde)
);

CREATE TABLE tasa_interes (
    id_tasa_interes  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto         VARCHAR(10)  NOT NULL CHECK (producto IN ('prestamo','tarjeta')),
    porcentaje       NUMERIC(7,4) NOT NULL CHECK (porcentaje >= 0),   -- tasa efectiva anual
    vigente_desde    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    id_administrador INTEGER      NOT NULL REFERENCES empleado(id_empleado),
    CONSTRAINT uq_tasa_interes UNIQUE (producto, vigente_desde)
);

-- =====================================================================
-- 4. CUENTAS Y TRANSACCIONES (HU-01 a HU-06)
-- =====================================================================

CREATE TABLE cuenta (
    num_cuenta     VARCHAR(20)   PRIMARY KEY,
    id_cliente     INTEGER       NOT NULL REFERENCES cliente(id_cliente),
    id_tipo_cuenta SMALLINT      NOT NULL REFERENCES tipo_cuenta(id_tipo_cuenta),
    codigo_moneda  CHAR(3)       NOT NULL REFERENCES moneda(codigo_iso),
    saldo          NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (saldo >= 0),   -- HU-01: inicia en cero
    estado         VARCHAR(10)   NOT NULL DEFAULT 'activa'
                   CHECK (estado IN ('activa','bloqueada','inactiva')),
    fecha_apertura TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE transaccion (
    id_transaccion      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo                VARCHAR(20)   NOT NULL
                        CHECK (tipo IN ('deposito','retiro','transf_propia','transf_intl','pago_tarjeta')),
    num_cuenta          VARCHAR(20)   NOT NULL REFERENCES cuenta(num_cuenta),         -- cuenta afectada / origen
    num_cuenta_destino  VARCHAR(20)   REFERENCES cuenta(num_cuenta),                  -- solo transf_propia
    monto               NUMERIC(18,2) NOT NULL CHECK (monto > 0),                     -- HU-06 esc.2
    fecha_hora          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    estado              VARCHAR(12)   NOT NULL DEFAULT 'completada'
                        CHECK (estado IN ('completada','rechazada','reversada')),
    descripcion         VARCHAR(200),
    CONSTRAINT ck_transaccion_destino CHECK (
        (tipo = 'transf_propia' AND num_cuenta_destino IS NOT NULL AND num_cuenta_destino <> num_cuenta)
        OR (tipo <> 'transf_propia' AND num_cuenta_destino IS NULL)
    )
);

CREATE TABLE transferencia_internacional (
    id_transaccion          BIGINT PRIMARY KEY REFERENCES transaccion(id_transaccion) ON DELETE CASCADE,
    id_tasa_cambio          INTEGER       NOT NULL REFERENCES tasa_cambio(id_tasa_cambio),
    moneda_destino          CHAR(3)       NOT NULL REFERENCES moneda(codigo_iso),
    monto_convertido        NUMERIC(18,2) NOT NULL CHECK (monto_convertido > 0),
    pais_destino            VARCHAR(60)   NOT NULL,
    beneficiario            VARCHAR(150)  NOT NULL,
    cuenta_destino_externa  VARCHAR(40)   NOT NULL        -- IBAN / numero de cuenta externo
);

-- =====================================================================
-- 5. SOLICITUDES, TARJETAS Y PRESTAMOS (HU-07 a HU-14)
-- =====================================================================

CREATE TABLE solicitud (
    id_solicitud     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente       INTEGER     NOT NULL REFERENCES cliente(id_cliente),
    tipo             VARCHAR(10) NOT NULL CHECK (tipo IN ('tarjeta','prestamo')),
    num_cuenta       VARCHAR(20) NOT NULL REFERENCES cuenta(num_cuenta),   -- cuenta asociada / de desembolso
    fecha_solicitud  TIMESTAMPTZ NOT NULL DEFAULT now(),
    estado           VARCHAR(12) NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','en_evaluacion','aprobada','rechazada')),
    id_asesor        INTEGER     REFERENCES empleado(id_empleado),         -- asesor asignado / responsable
    fecha_resolucion TIMESTAMPTZ,
    motivo_rechazo   VARCHAR(300),
    monto            NUMERIC(18,2) CHECK (monto > 0),                      -- solo prestamo
    plazo_meses      SMALLINT      CHECK (plazo_meses > 0),                -- solo prestamo
    proposito        VARCHAR(200),                                         -- solo prestamo
    CONSTRAINT ck_solicitud_prestamo CHECK (
        tipo <> 'prestamo' OR (monto IS NOT NULL AND plazo_meses IS NOT NULL AND proposito IS NOT NULL)
    ),
    CONSTRAINT ck_solicitud_resolucion CHECK (
        estado NOT IN ('aprobada','rechazada')
        OR (id_asesor IS NOT NULL AND fecha_resolucion IS NOT NULL)        -- HU-14
    ),
    CONSTRAINT ck_solicitud_rechazo CHECK (estado <> 'rechazada' OR motivo_rechazo IS NOT NULL)
);

CREATE TABLE tarjeta_credito (
    num_tarjeta       VARCHAR(19)   PRIMARY KEY,
    id_solicitud      INTEGER       NOT NULL UNIQUE REFERENCES solicitud(id_solicitud),
    num_cuenta        VARCHAR(20)   NOT NULL REFERENCES cuenta(num_cuenta),
    cupo_total        NUMERIC(18,2) NOT NULL CHECK (cupo_total >= 0),
    cupo_utilizado    NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (cupo_utilizado >= 0),
    cupo_disponible   NUMERIC(18,2) GENERATED ALWAYS AS (cupo_total - cupo_utilizado) STORED,   -- HU-09
    pago_minimo       NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (pago_minimo >= 0),
    fecha_vencimiento_pago DATE,
    estado            VARCHAR(10)   NOT NULL DEFAULT 'activa'
                      CHECK (estado IN ('activa','bloqueada','cancelada')),
    fecha_emision     DATE          NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT ck_tarjeta_cupo CHECK (cupo_utilizado <= cupo_total)
);

CREATE TABLE pago_tarjeta (                              -- HU-08
    id_pago        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    num_tarjeta    VARCHAR(19)   NOT NULL REFERENCES tarjeta_credito(num_tarjeta),
    id_transaccion BIGINT        NOT NULL UNIQUE REFERENCES transaccion(id_transaccion),   -- debito en la cuenta
    monto          NUMERIC(18,2) NOT NULL CHECK (monto > 0),
    modalidad      VARCHAR(6)    NOT NULL CHECK (modalidad IN ('total','minimo')),
    fecha_hora     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE prestamo (
    id_prestamo      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_solicitud     INTEGER       NOT NULL UNIQUE REFERENCES solicitud(id_solicitud),
    num_cuenta       VARCHAR(20)   NOT NULL REFERENCES cuenta(num_cuenta),
    id_tasa_interes  INTEGER       NOT NULL REFERENCES tasa_interes(id_tasa_interes),
    monto_aprobado   NUMERIC(18,2) NOT NULL CHECK (monto_aprobado > 0),
    plazo_meses      SMALLINT      NOT NULL CHECK (plazo_meses > 0),
    tasa_aplicada    NUMERIC(7,4)  NOT NULL CHECK (tasa_aplicada >= 0),  -- congelada al aprobar (HU-15 esc.2)
    fecha_desembolso DATE          NOT NULL DEFAULT CURRENT_DATE,
    estado           VARCHAR(10)   NOT NULL DEFAULT 'activo'
                     CHECK (estado IN ('activo','en_mora','pagado'))
);

CREATE TABLE cuota (                                     -- HU-11
    id_prestamo       INTEGER       NOT NULL REFERENCES prestamo(id_prestamo) ON DELETE CASCADE,
    num_cuota         SMALLINT      NOT NULL CHECK (num_cuota > 0),
    fecha_vencimiento DATE          NOT NULL,
    valor_capital     NUMERIC(18,2) NOT NULL CHECK (valor_capital >= 0),
    valor_interes     NUMERIC(18,2) NOT NULL CHECK (valor_interes >= 0),
    interes_mora      NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (interes_mora >= 0),
    estado            VARCHAR(10)   NOT NULL DEFAULT 'pendiente'
                      CHECK (estado IN ('pendiente','pagada','vencida')),
    fecha_pago        DATE,
    PRIMARY KEY (id_prestamo, num_cuota),
    CONSTRAINT ck_cuota_pago CHECK ((estado = 'pagada') = (fecha_pago IS NOT NULL))
);

-- =====================================================================
-- 6. INDICES
-- =====================================================================
CREATE INDEX ix_cliente_asesor        ON cliente(id_asesor);
CREATE INDEX ix_cliente_perfil        ON cliente(id_perfil);
CREATE INDEX ix_documento_cliente     ON documento(id_cliente);
CREATE INDEX ix_cuenta_cliente        ON cuenta(id_cliente);
CREATE INDEX ix_transaccion_cuenta_fh ON transaccion(num_cuenta, fecha_hora DESC);   -- HU-02 esc.2
CREATE INDEX ix_transaccion_destino   ON transaccion(num_cuenta_destino) WHERE num_cuenta_destino IS NOT NULL;
CREATE INDEX ix_tasa_cambio_vigente   ON tasa_cambio(moneda_origen, moneda_destino, vigente_desde DESC);
CREATE INDEX ix_solicitud_cliente     ON solicitud(id_cliente);
CREATE INDEX ix_solicitud_asesor_est  ON solicitud(id_asesor, estado);
CREATE INDEX ix_tarjeta_cuenta        ON tarjeta_credito(num_cuenta);
CREATE INDEX ix_prestamo_cuenta       ON prestamo(num_cuenta);
CREATE INDEX ix_cuota_vencimiento     ON cuota(fecha_vencimiento) WHERE estado <> 'pagada';

-- =====================================================================
-- 7. REGLAS DE NEGOCIO (TRIGGERS)
-- =====================================================================

-- 7.1 Aplica el movimiento al saldo: valida cuenta activa, saldo suficiente
--     (HU-03 esc.2, HU-05 esc.2, HU-02 esc.3) y que las cuentas propias
--     pertenezcan al mismo cliente y moneda (HU-03).
CREATE OR REPLACE FUNCTION fn_aplicar_transaccion() RETURNS trigger AS $$
DECLARE
    v_origen  cuenta%ROWTYPE;
    v_destino cuenta%ROWTYPE;
BEGIN
    IF NEW.estado <> 'completada' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_origen FROM cuenta WHERE num_cuenta = NEW.num_cuenta FOR UPDATE;
    IF v_origen.estado <> 'activa' THEN
        RAISE EXCEPTION 'La cuenta % no esta disponible (estado: %)', v_origen.num_cuenta, v_origen.estado;
    END IF;

    IF NEW.tipo = 'deposito' THEN
        UPDATE cuenta SET saldo = saldo + NEW.monto WHERE num_cuenta = NEW.num_cuenta;
    ELSE
        IF v_origen.saldo < NEW.monto THEN
            RAISE EXCEPTION 'Saldo insuficiente en la cuenta %', v_origen.num_cuenta;
        END IF;
        UPDATE cuenta SET saldo = saldo - NEW.monto WHERE num_cuenta = NEW.num_cuenta;

        IF NEW.tipo = 'transf_propia' THEN
            SELECT * INTO v_destino FROM cuenta WHERE num_cuenta = NEW.num_cuenta_destino FOR UPDATE;
            IF v_destino.id_cliente <> v_origen.id_cliente THEN
                RAISE EXCEPTION 'La cuenta destino no pertenece al mismo cliente';
            END IF;
            IF v_destino.codigo_moneda <> v_origen.codigo_moneda THEN
                RAISE EXCEPTION 'Las cuentas propias deben tener la misma moneda';
            END IF;
            IF v_destino.estado <> 'activa' THEN
                RAISE EXCEPTION 'La cuenta destino % no esta activa', v_destino.num_cuenta;
            END IF;
            UPDATE cuenta SET saldo = saldo + NEW.monto WHERE num_cuenta = NEW.num_cuenta_destino;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_aplicar_transaccion
    BEFORE INSERT ON transaccion
    FOR EACH ROW EXECUTE FUNCTION fn_aplicar_transaccion();

-- 7.2 Transferencia internacional: tasa vigente, moneda soportada y limite diario (HU-04).
CREATE OR REPLACE FUNCTION fn_validar_transf_intl() RETURNS trigger AS $$
DECLARE
    v_tx       transaccion%ROWTYPE;
    v_cuenta   cuenta%ROWTYPE;
    v_tasa     tasa_cambio%ROWTYPE;
    v_limite   NUMERIC;
    v_acum     NUMERIC;
BEGIN
    SELECT * INTO v_tx FROM transaccion WHERE id_transaccion = NEW.id_transaccion;
    IF v_tx.tipo <> 'transf_intl' THEN
        RAISE EXCEPTION 'La transaccion % no es de tipo transf_intl', NEW.id_transaccion;
    END IF;
    SELECT * INTO v_cuenta FROM cuenta WHERE num_cuenta = v_tx.num_cuenta;

    SELECT * INTO v_tasa FROM tasa_cambio WHERE id_tasa_cambio = NEW.id_tasa_cambio;
    IF v_tasa.moneda_origen <> v_cuenta.codigo_moneda OR v_tasa.moneda_destino <> NEW.moneda_destino THEN
        RAISE EXCEPTION 'La tasa de cambio no corresponde al par % -> %', v_cuenta.codigo_moneda, NEW.moneda_destino;
    END IF;
    IF v_tasa.vigente_hasta IS NOT NULL AND v_tasa.vigente_hasta < v_tx.fecha_hora THEN
        RAISE EXCEPTION 'La tasa de cambio % ya no esta vigente', v_tasa.id_tasa_cambio;
    END IF;
    IF NOT (SELECT soportada FROM moneda WHERE codigo_iso = NEW.moneda_destino) THEN
        RAISE EXCEPTION 'La moneda % no esta disponible', NEW.moneda_destino;
    END IF;

    -- Limite diario del perfil (expresado en la moneda de la cuenta origen)
    SELECT p.limite_diario_transf_intl INTO v_limite
      FROM cliente c JOIN perfil p USING (id_perfil) WHERE c.id_cliente = v_cuenta.id_cliente;

    SELECT COALESCE(SUM(t.monto), 0) INTO v_acum
      FROM transaccion t JOIN cuenta c ON c.num_cuenta = t.num_cuenta
     WHERE c.id_cliente = v_cuenta.id_cliente
       AND t.tipo = 'transf_intl' AND t.estado = 'completada'
       AND t.fecha_hora::date = v_tx.fecha_hora::date;       -- incluye la transaccion actual
    IF v_acum > v_limite THEN
        RAISE EXCEPTION 'Se supero el limite diario de transferencias internacionales (%)', v_limite;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_validar_transf_intl
    AFTER INSERT ON transferencia_internacional
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_validar_transf_intl();

-- 7.3 Pago de tarjeta: libera cupo (HU-08).
CREATE OR REPLACE FUNCTION fn_aplicar_pago_tarjeta() RETURNS trigger AS $$
DECLARE
    v_tarjeta tarjeta_credito%ROWTYPE;
    v_tx      transaccion%ROWTYPE;
BEGIN
    SELECT * INTO v_tx FROM transaccion WHERE id_transaccion = NEW.id_transaccion;
    IF v_tx.tipo <> 'pago_tarjeta' OR v_tx.monto <> NEW.monto THEN
        RAISE EXCEPTION 'La transaccion % no corresponde a este pago', NEW.id_transaccion;
    END IF;

    SELECT * INTO v_tarjeta FROM tarjeta_credito WHERE num_tarjeta = NEW.num_tarjeta FOR UPDATE;
    IF NEW.monto > v_tarjeta.cupo_utilizado THEN
        RAISE EXCEPTION 'El pago supera el saldo pendiente de la tarjeta';
    END IF;
    IF NEW.modalidad = 'total' AND NEW.monto <> v_tarjeta.cupo_utilizado THEN
        RAISE EXCEPTION 'El pago total debe ser igual al saldo pendiente (%)', v_tarjeta.cupo_utilizado;
    END IF;
    IF NEW.modalidad = 'minimo' AND NEW.monto < v_tarjeta.pago_minimo THEN
        RAISE EXCEPTION 'El pago minimo no puede ser inferior a %', v_tarjeta.pago_minimo;
    END IF;

    UPDATE tarjeta_credito SET cupo_utilizado = cupo_utilizado - NEW.monto
     WHERE num_tarjeta = NEW.num_tarjeta;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_aplicar_pago_tarjeta
    BEFORE INSERT ON pago_tarjeta
    FOR EACH ROW EXECUTE FUNCTION fn_aplicar_pago_tarjeta();

-- 7.4 Solicitudes: solo un asesor puede resolver; el monto del prestamo respeta el perfil (HU-10, HU-14).
CREATE OR REPLACE FUNCTION fn_validar_solicitud() RETURNS trigger AS $$
DECLARE
    v_max NUMERIC;
BEGIN
    IF NEW.id_asesor IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM empleado WHERE id_empleado = NEW.id_asesor AND rol = 'asesor' AND activo) THEN
        RAISE EXCEPTION 'El empleado % no es un asesor activo', NEW.id_asesor;
    END IF;

    IF NEW.tipo = 'prestamo' AND TG_OP = 'INSERT' THEN
        SELECT p.monto_max_prestamo INTO v_max
          FROM cliente c JOIN perfil p USING (id_perfil) WHERE c.id_cliente = NEW.id_cliente;
        IF NEW.monto > v_max THEN
            RAISE EXCEPTION 'Monto fuera del rango permitido. Maximo disponible: %', v_max;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_solicitud
    BEFORE INSERT OR UPDATE ON solicitud
    FOR EACH ROW EXECUTE FUNCTION fn_validar_solicitud();

-- 7.5 Administrador: solo empleados con rol administrador configuran tasas (HU-15).
CREATE OR REPLACE FUNCTION fn_validar_admin() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM empleado WHERE id_empleado = NEW.id_administrador AND rol = 'administrador') THEN
        RAISE EXCEPTION 'El empleado % no es administrador', NEW.id_administrador;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_admin_tasa_cambio  BEFORE INSERT OR UPDATE ON tasa_cambio
    FOR EACH ROW EXECUTE FUNCTION fn_validar_admin();
CREATE TRIGGER trg_admin_tasa_interes BEFORE INSERT OR UPDATE ON tasa_interes
    FOR EACH ROW EXECUTE FUNCTION fn_validar_admin();

-- 7.6 Al registrar una nueva tasa de cambio se cierra la vigencia de la anterior (HU-15 esc.1).
CREATE OR REPLACE FUNCTION fn_cerrar_tasa_cambio() RETURNS trigger AS $$
BEGIN
    UPDATE tasa_cambio
       SET vigente_hasta = NEW.vigente_desde
     WHERE moneda_origen = NEW.moneda_origen AND moneda_destino = NEW.moneda_destino
       AND vigente_hasta IS NULL AND id_tasa_cambio <> NEW.id_tasa_cambio
       AND vigente_desde < NEW.vigente_desde;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cerrar_tasa_cambio AFTER INSERT ON tasa_cambio
    FOR EACH ROW EXECUTE FUNCTION fn_cerrar_tasa_cambio();

-- =====================================================================
-- 8. VISTAS DE CONSULTA
-- =====================================================================

-- HU-02: movimientos de una cuenta (una fila por cuenta afectada, cronologico)
CREATE VIEW v_movimientos AS
SELECT t.num_cuenta, t.id_transaccion, t.fecha_hora, t.tipo, t.monto,
       CASE WHEN t.tipo = 'deposito' THEN 'credito' ELSE 'debito' END AS naturaleza,
       t.estado, t.descripcion
  FROM transaccion t
UNION ALL
SELECT t.num_cuenta_destino, t.id_transaccion, t.fecha_hora, t.tipo, t.monto,
       'credito', t.estado, t.descripcion
  FROM transaccion t
 WHERE t.num_cuenta_destino IS NOT NULL;

-- HU-09: cupo de tarjetas activas
CREATE VIEW v_cupo_tarjeta AS
SELECT t.num_tarjeta, c.id_cliente, t.cupo_total, t.cupo_utilizado, t.cupo_disponible
  FROM tarjeta_credito t JOIN cuenta c USING (num_cuenta)
 WHERE t.estado = 'activa';

-- HU-11: cronograma de pagos y mora
CREATE VIEW v_cronograma_prestamo AS
SELECT p.id_prestamo, c.num_cuota, c.fecha_vencimiento, c.valor_capital, c.valor_interes,
       c.interes_mora, p.tasa_aplicada,
       CASE WHEN c.estado = 'pendiente' AND c.fecha_vencimiento < CURRENT_DATE
            THEN 'vencida' ELSE c.estado END AS estado_cuota,
       BOOL_OR(c.estado <> 'pagada' AND c.fecha_vencimiento < CURRENT_DATE)
           OVER (PARTITION BY p.id_prestamo) AS prestamo_en_mora
  FROM prestamo p JOIN cuota c USING (id_prestamo);

-- HU-12: beneficios vigentes por cliente (los vencidos no aparecen)
CREATE VIEW v_beneficios_cliente AS
SELECT DISTINCT c.id_cliente, b.id_beneficio, b.descripcion, b.vigente_desde, b.vigente_hasta
  FROM cliente c
  LEFT JOIN cuenta cu ON cu.id_cliente = c.id_cliente
  JOIN beneficio b ON TRUE
 WHERE (b.vigente_hasta IS NULL OR b.vigente_hasta >= CURRENT_DATE)
   AND b.vigente_desde <= CURRENT_DATE
   AND (EXISTS (SELECT 1 FROM perfil_beneficio pb
                 WHERE pb.id_beneficio = b.id_beneficio AND pb.id_perfil = c.id_perfil)
     OR EXISTS (SELECT 1 FROM tipo_cuenta_beneficio tb
                 WHERE tb.id_beneficio = b.id_beneficio AND tb.id_tipo_cuenta = cu.id_tipo_cuenta));

-- HU-13: el asesor solo ve a sus clientes asignados
CREATE VIEW v_clientes_asesor AS
SELECT c.id_asesor, c.id_cliente, c.num_identificacion, c.nombres, c.apellidos,
       cu.num_cuenta, cu.saldo, cu.codigo_moneda
  FROM cliente c LEFT JOIN cuenta cu USING (id_cliente)
 WHERE c.id_asesor IS NOT NULL;
-- Uso: SELECT * FROM v_clientes_asesor WHERE id_asesor = :asesor AND num_identificacion = :doc;

-- Tasa de cambio vigente
CREATE VIEW v_tasa_cambio_vigente AS
SELECT DISTINCT ON (moneda_origen, moneda_destino) *
  FROM tasa_cambio
 WHERE vigente_desde <= now() AND (vigente_hasta IS NULL OR vigente_hasta > now())
 ORDER BY moneda_origen, moneda_destino, vigente_desde DESC;

-- =====================================================================
-- 9. DATOS SEMILLA
-- =====================================================================
INSERT INTO moneda (codigo_iso, nombre) VALUES
  ('COP','Peso colombiano'), ('USD','Dolar estadounidense'), ('EUR','Euro');
INSERT INTO tipo_cuenta (nombre) VALUES ('ahorros'), ('corriente');
INSERT INTO perfil (nombre, puntaje_crediticio_min, limite_diario_transf_intl, monto_max_prestamo) VALUES
  ('Basico',  0,   5000, 10000),
  ('Premium', 700, 25000, 100000);
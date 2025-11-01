WITH
-- 1. Base ICU stays for 78–88 y.o. men
icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- 2. Flag HHS diagnoses
hhs_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%hyperosmolar%' THEN 1 ELSE 0 END) AS is_hhs
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
  ON
    d.icd_code = diag.icd_code
    AND d.icd_version = diag.icd_version
  GROUP BY
    d.subject_id,
    d.hadm_id
),

-- 3a. First 48h composite instability score placeholder
first48_instability AS (
  SELECT
    b.stay_id,
    -- placeholder for actual composite score logic
    SUM(1) * 1.0 AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN
    icu_base AS b
  ON
    ce.stay_id = b.stay_id
  WHERE
    ce.charttime BETWEEN b.intime
                     AND TIMESTAMP_ADD(b.intime, INTERVAL 48 HOUR)
  GROUP BY
    b.stay_id
),

-- 3b. First 48h abnormal vital burden placeholder
first48_abnormal AS (
  SELECT
    b.stay_id,
    -- placeholder for actual abnormal vital burden logic
    AVG(1) AS abnormal_burden
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN
    icu_base AS b
  ON
    ce.stay_id = b.stay_id
  WHERE
    ce.charttime BETWEEN b.intime
                     AND TIMESTAMP_ADD(b.intime, INTERVAL 48 HOUR)
  GROUP BY
    b.stay_id
),

-- 3c. ICU mortality: join back to admissions
icu_mortality AS (
  SELECT
    b.stay_id,
    a.hospital_expire_flag AS died_in_hospital
  FROM
    icu_base AS b
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON
    b.hadm_id = a.hadm_id
),

-- 4. Combine everything
stay_metrics AS (
  SELECT
    b.stay_id,
    CASE WHEN f.is_hhs = 1 THEN 'HHS' ELSE 'Control' END AS group_label,
    inst.instability_score,
    abd.abnormal_burden,
    b.los,
    m.died_in_hospital
  FROM
    icu_base AS b
  LEFT JOIN
    hhs_flags AS f
  ON
    b.subject_id = f.subject_id
    AND b.hadm_id = f.hadm_id
  LEFT JOIN
    first48_instability AS inst
  ON
    b.stay_id = inst.stay_id
  LEFT JOIN
    first48_abnormal AS abd
  ON
    b.stay_id = abd.stay_id
  LEFT JOIN
    icu_mortality AS m
  ON
    b.stay_id = m.stay_id
)

-- 5. Final percentiles by group
SELECT
  group_label,

  -- Composite instability score quartiles
  quartiles_inst[OFFSET(1)] AS instability_p25,
  quartiles_inst[OFFSET(2)] AS instability_median,
  quartiles_inst[OFFSET(3)] AS instability_p75,

  -- Abnormal vital burden quartiles
  quartiles_abd[OFFSET(1)] AS burden_p25,
  quartiles_abd[OFFSET(2)] AS burden_median,
  quartiles_abd[OFFSET(3)] AS burden_p75,

  -- ICU LOS quartiles
  quartiles_los[OFFSET(1)] AS los_p25,
  quartiles_los[OFFSET(2)] AS los_median,
  quartiles_los[OFFSET(3)] AS los_p75,

  -- Mortality rate
  SAFE_DIVIDE(died_sum, cnt) AS mortality_rate

FROM (
  SELECT
    group_label,
    APPROX_QUANTILES(instability_score, 4) AS quartiles_inst,
    APPROX_QUANTILES(abnormal_burden, 4) AS quartiles_abd,
    APPROX_QUANTILES(los, 4) AS quartiles_los,
    SUM(died_in_hospital) AS died_sum,
    COUNT(*) AS cnt
  FROM
    stay_metrics
  GROUP BY
    group_label
);
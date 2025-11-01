WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age,
    DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 70 AND 80
),

lower_gi_bleed AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.icd_code = 'K922' AND d.icd_version = 10
),

complications AS (
  SELECT
    lgb.hadm_id,
    COUNT(DISTINCT icu.stay_id) AS icu_flag,
    MAX(CASE WHEN mv.itemid IS NOT NULL THEN 1 ELSE 0 END) AS mech_vent_flag,
    MAX(CASE WHEN vaso.itemid IS NOT NULL THEN 1 ELSE 0 END) AS vaso_flag,
    MAX(CASE WHEN dial.itemid IS NOT NULL THEN 1 ELSE 0 END) AS dialysis_flag
  FROM
    lower_gi_bleed lgb
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    lgb.hadm_id = icu.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` mv
  ON
    icu.stay_id = mv.stay_id
    AND mv.itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE LOWER(label) LIKE '%ventilation%'
    )
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` vaso
  ON
    icu.stay_id = vaso.stay_id
    AND vaso.itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE LOWER(label) LIKE '%norepinephrine%' OR LOWER(label) LIKE '%epinephrine%' OR LOWER(label) LIKE '%vasopressin%'
    )
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` dial
  ON
    icu.stay_id = dial.stay_id
    AND dial.itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE LOWER(label) LIKE '%dialysis%'
    )
  GROUP BY
    lgb.hadm_id
),

risk_score AS (
  SELECT
    lgb.*,
    COALESCE(c.icu_flag, 0) +
    COALESCE(c.mech_vent_flag, 0) +
    COALESCE(c.vaso_flag, 0) +
    COALESCE(c.dialysis_flag, 0) AS risk_score
  FROM
    lower_gi_bleed lgb
  LEFT JOIN
    complications c
  ON
    lgb.hadm_id = c.hadm_id
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    risk_score
),

outcomes AS (
  SELECT
    risk_quintile,
    COUNT(*) AS n,
    AVG(CASE
      WHEN dod IS NOT NULL AND dod <= DATETIME_ADD(admittime, INTERVAL 90 DAY) THEN 1
      ELSE 0
    END) AS mortality_90d,
    AVG(CASE WHEN risk_score > 0 THEN 1 ELSE 0 END) AS major_complication_rate,
    (PERCENTILE_CONT(
      CASE
        WHEN (dod IS NULL OR dod > DATETIME_ADD(admittime, INTERVAL 90 DAY)) THEN DATETIME_DIFF(dischtime, admittime, DAY)
        ELSE NULL
      END, 0.5) OVER (PARTITION BY risk_quintile)).value AS median_los_90d_survivors
  FROM
    quintiles
  GROUP BY
    risk_quintile
)

SELECT
  risk_quintile,
  n,
  ROUND(mortality_90d, 4) AS mortality_90d_rate,
  ROUND(major_complication_rate, 4) AS major_complication_rate,
  median_los_90d_survivors
FROM
  outcomes
ORDER BY
  risk_quintile;
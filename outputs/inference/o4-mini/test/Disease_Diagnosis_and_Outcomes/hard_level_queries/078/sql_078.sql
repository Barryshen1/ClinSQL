WITH hf_admissions AS (
  -- female 59–69 with heart failure
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.deathtime, a.admittime, DAY) AS survival_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_hf
      ON d_hf.icd_code = dd_hf.icd_code
      AND d_hf.icd_version = dd_hf.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(dd_hf.long_title) LIKE '%heart failure%'
),
aki_flags AS (
  -- flag AKI per admission
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute kidney injury%' THEN 1 ELSE 0 END) AS aki_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
ards_flags AS (
  -- flag ARDS per admission
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%' THEN 1 ELSE 0 END) AS ards_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
cohort AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hospital_expire_flag AS in_hosp_death,
    COALESCE(a.aki_flag, 0) AS aki_flag,
    COALESCE(r.ards_flag, 0) AS ards_flag,
    h.survival_days,
    -- composite risk score = sum of flags
    (h.hospital_expire_flag
     + COALESCE(a.aki_flag, 0)
     + COALESCE(r.ards_flag, 0)
    ) AS risk_score
  FROM hf_admissions h
  LEFT JOIN aki_flags a
    USING(subject_id, hadm_id)
  LEFT JOIN ards_flags r
    USING(subject_id, hadm_id)
),
quantiles AS (
  -- compute risk_score percentiles
  SELECT
    APPROX_QUANTILES(risk_score, 100) AS rq
  FROM cohort
),
median_survival AS (
  -- median survival days among in-hospital deaths
  SELECT
    PERCENTILE_CONT(survival_days, 0.50) AS median_survival_days
  FROM cohort
  WHERE in_hosp_death = 1
)
SELECT
  COUNT(*) AS N,
  SAFE_DIVIDE(SUM(in_hosp_death), COUNT(*)) AS in_hosp_mortality_rate,
  SAFE_DIVIDE(SUM(aki_flag), COUNT(*))         AS aki_rate,
  SAFE_DIVIDE(SUM(ards_flag), COUNT(*))        AS ards_rate,
  ANY_VALUE(ms.median_survival_days)           AS median_survival_days,
  ANY_VALUE(q.rq[SAFE_OFFSET(0)])              AS risk_min,
  ANY_VALUE(q.rq[SAFE_OFFSET(25)])             AS risk_p25,
  ANY_VALUE(q.rq[SAFE_OFFSET(50)])             AS risk_median,
  ANY_VALUE(q.rq[SAFE_OFFSET(75)])             AS risk_p75,
  ANY_VALUE(q.rq[SAFE_OFFSET(90)])             AS risk_p90,
  ANY_VALUE(q.rq[SAFE_OFFSET(100)])            AS risk_max
FROM cohort
CROSS JOIN quantiles q
CROSS JOIN median_survival ms;
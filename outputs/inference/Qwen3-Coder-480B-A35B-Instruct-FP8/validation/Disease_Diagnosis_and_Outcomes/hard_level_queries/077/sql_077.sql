WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
risk_scores AS (
  SELECT
    hadm_id,
    anchor_age AS risk_score
  FROM pneumonia_admissions
),
aki_cases AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM
    pneumonia_admissions pa
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON pa.hadm_id = le.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'creatinine'
    AND (
      le.valuenum > 3.0
      OR le.valuenum > 1.5 * (
        SELECT MIN(l2.valuenum)
        FROM physionet-data.mimiciv_3_1_hosp.labevents l2
        JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di2
          ON l2.itemid = di2.itemid
        WHERE l2.hadm_id = le.hadm_id
          AND LOWER(di2.label) = 'creatinine'
          AND l2.valuenum IS NOT NULL
      )
    )
),
ards_cases AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM
    pneumonia_admissions pa
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON pa.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) IN ('pao2/fio2', 'po2/fio2')
    AND ce.valuenum < 300
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_icu.chartevents ce2
      JOIN physionet-data.mimiciv_3_1_icu.d_items di2
        ON ce2.itemid = di2.itemid
      WHERE ce2.stay_id = ce.stay_id
        AND LOWER(di2.label) = 'peep'
        AND ce2.valuenum > 5
    )
)
SELECT
  COUNT(*) AS cohort_size,
  APPROX_QUANTILES(rs.risk_score, 100)[OFFSET(0)] AS risk_score_min,
  APPROX_QUANTILES(rs.risk_score, 100)[OFFSET(25)] AS risk_score_25th,
  APPROX_QUANTILES(rs.risk_score, 100)[OFFSET(50)] AS risk_score_median,
  APPROX_QUANTILES(rs.risk_score, 100)[OFFSET(75)] AS risk_score_75th,
  APPROX_QUANTILES(rs.risk_score, 100)[OFFSET(100)] AS risk_score_max,
  AVG(CAST(pa.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
  AVG(CASE WHEN aki.hadm_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS aki_rate,
  AVG(CASE WHEN ards.hadm_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS ards_rate,
  APPROX_QUANTILES(
    CASE 
      WHEN pa.hospital_expire_flag = 1 THEN 
        DATE_DIFF(pa.dischtime, pa.admittime, DAY)
      ELSE 
        NULL 
    END, 2
  )[OFFSET(1)] AS median_survival_days_decedents
FROM
  pneumonia_admissions pa
JOIN
  risk_scores rs
  ON pa.hadm_id = rs.hadm_id
LEFT JOIN
  aki_cases aki
  ON pa.hadm_id = aki.hadm_id
LEFT JOIN
  ards_cases ards
  ON pa.hadm_id = ards.hadm_id;
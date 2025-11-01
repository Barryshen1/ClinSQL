WITH hf_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- Heart failure ICD codes: 428.* (ICD9) or I50.* (ICD10)
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
)
, dx_flags AS (
  SELECT
    h.*,
    -- AKI flag
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        THEN 1 ELSE 0
      END
    ) AS aki_flag,
    -- ARDS flag
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND (d.icd_code = '51882' OR d.icd_code = '51885'))
          OR (d.icd_version = 10 AND d.icd_code = 'J80')
        THEN 1 ELSE 0
      END
    ) AS ards_flag
  FROM hf_cohort h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON h.hadm_id = d.hadm_id
  GROUP BY h.subject_id, h.hadm_id, h.anchor_age, h.gender,
           h.admittime, h.dischtime, h.deathtime, h.hospital_expire_flag
)
, scored AS (
  SELECT
    *,
    hospital_expire_flag AS mortality_flag,
    -- survival in days if died in hospital
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL
      THEN DATETIME_DIFF(deathtime, admittime, DAY)
    END AS survival_days,
    -- Composite risk score
    (hospital_expire_flag + aki_flag + ards_flag) AS composite_score
  FROM dx_flags
)
SELECT
  COUNT(*) AS n_admissions,
  AVG(mortality_flag) AS mortality_rate,
  AVG(aki_flag) AS aki_rate,
  AVG(ards_flag) AS ards_rate,
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days_among_deaths,
  MIN(composite_score) AS comp_min,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS comp_p25,
  APPROX_QUANTILES(composite_score, 2)[OFFSET(1)] AS comp_median,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS comp_p75,
  APPROX_QUANTILES(composite_score, 10)[OFFSET(9)] AS comp_p90,
  MAX(composite_score) AS comp_max
FROM scored;
WITH ami_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Flag major complication
    IF(SUM(
      CASE
        WHEN (d.icd_version = 9 AND (
              d.icd_code LIKE '428%' OR  -- CHF
              d.icd_code = '4275'  OR    -- Cardiac arrest
              d.icd_code = '78551' OR    -- Cardiogenic shock
              d.icd_code LIKE '584%'    -- Acute renal failure
            ))
         OR (d.icd_version = 10 AND (
              d.icd_code LIKE 'I50%' OR  -- CHF
              d.icd_code LIKE 'I46%' OR  -- Cardiac arrest
              d.icd_code = 'R570'  OR    -- Cardiogenic shock
              d.icd_code LIKE 'N17%'    -- Acute kidney failure
            ))
        THEN 1 ELSE 0
      END
    ) > 0, 1, 0) AS major_complication_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
  GROUP BY p.subject_id, a.hadm_id, p.gender, p.anchor_age,
           a.hospital_expire_flag, a.admittime, a.dischtime
),
risk_scored AS (
  SELECT
    *,
    anchor_age + major_complication_flag * 10 AS risk_score
  FROM ami_cohort
),
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM risk_scored
)
SELECT
  risk_quintile,
  COUNT(*) AS admissions,
  100 * SUM(hospital_expire_flag) / COUNT(*) AS in_hosp_mortality_pct,
  100 * SUM(major_complication_flag) / COUNT(*) AS major_complication_pct,
  PERCENTILE_CONT(IF(hospital_expire_flag = 0 AND los >= 0, los, NULL), 0.5) 
    OVER (PARTITION BY risk_quintile) AS median_survivor_los
FROM quintiled
GROUP BY risk_quintile
ORDER BY risk_quintile;
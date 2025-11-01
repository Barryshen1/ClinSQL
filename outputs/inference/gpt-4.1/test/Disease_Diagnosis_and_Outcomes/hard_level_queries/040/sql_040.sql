WITH ich_admissions AS (
  -- Identify admissions for females aged 69-79 with ICH
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    adm.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 69 AND 79
    AND (
      -- ICD-10 ICH codes
      (dx.icd_version = 10 AND (
        dx.icd_code LIKE 'I61%' OR
        dx.icd_code LIKE 'I62%'
      ))
      -- ICD-9 ICH codes
      OR (dx.icd_version = 9 AND (
        dx.icd_code = '430' OR
        dx.icd_code = '431'
      ))
    )
),
cci AS (
  -- Calculate simplified Charlson Comorbidity Index per admission
  -- For brevity, count presence of major comorbidities
  SELECT
    hadm_id,
    SUM(
      CASE
        WHEN (icd_version = 10 AND icd_code LIKE 'I25%') OR (icd_version = 9 AND icd_code LIKE '414%') THEN 1 -- MI
        WHEN (icd_version = 10 AND icd_code LIKE 'I50%') OR (icd_version = 9 AND icd_code LIKE '428%') THEN 1 -- CHF
        WHEN (icd_version = 10 AND icd_code LIKE 'I63%') OR (icd_version = 9 AND icd_code LIKE '434%') THEN 1 -- Stroke
        WHEN (icd_version = 10 AND icd_code LIKE 'C%') OR (icd_version = 9 AND icd_code BETWEEN '140' AND '199') THEN 1 -- Cancer
        WHEN (icd_version = 10 AND icd_code LIKE 'N18%') OR (icd_version = 9 AND icd_code LIKE '585%') THEN 1 -- CKD
        ELSE 0
      END
    ) AS cci
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
complications AS (
  -- Identify major complications per admission
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 10 AND (
          icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR -- Sepsis
          icd_code LIKE 'N17%' OR -- Acute renal failure
          icd_code LIKE 'I46%' OR -- Cardiac arrest
          icd_code LIKE 'J18%'    -- Pneumonia
        ))
        OR (icd_version = 9 AND (
          icd_code = '99591' OR icd_code = '99592' OR -- Sepsis
          icd_code LIKE '584%' OR -- Acute renal failure
          icd_code = '4275' OR    -- Cardiac arrest
          icd_code = '486'        -- Pneumonia
        ))
        THEN 1 ELSE 0
      END
    ) AS major_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
scored_admissions AS (
  -- Merge and compute composite risk score
  SELECT
    ia.*,
    COALESCE(c.cci, 0) AS cci,
    COALESCE(comp.major_complication, 0) AS had_major_complication,
    -- Composite risk score: age + CCI + emergency admission
    ia.anchor_age + COALESCE(c.cci, 0) + IF(ia.admission_type = 'EMERGENCY', 1, 0) AS risk_score,
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) AS los_days
  FROM
    ich_admissions ia
    LEFT JOIN cci c ON ia.hadm_id = c.hadm_id
    LEFT JOIN complications comp ON ia.hadm_id = comp.hadm_id
),
quintiled AS (
  -- Assign quintiles by risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM
    scored_admissions
),
outcomes AS (
  -- Calculate outcomes per admission
  SELECT
    quintile,
    hadm_id,
    los_days,
    hospital_expire_flag,
    -- 30-day mortality: died within 30 days of admission
    CASE
      WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    had_major_complication
  FROM
    quintiled
)
SELECT
  quintile,
  COUNT(*) AS n,
  ROUND(100 * SUM(died_30d) / COUNT(*), 1) AS mortality_30d_pct,
  ROUND(100 * SUM(had_major_complication) / COUNT(*), 1) AS major_complication_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los_days
FROM
  outcomes
WHERE
  hospital_expire_flag = 0 -- survivors only for LOS
GROUP BY
  quintile
ORDER BY
  quintile
;
WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age,
    -- 30-day mortality (1 if death within 30 days, else 0)
    CASE
      WHEN pt.dod <= DATETIME_ADD(adm.admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Major complication: ICU admission during the stay (1 if any ICU stay, else 0)
    CASE
      WHEN icu.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS major_complication,
    -- LOS in days for survivors (NULL for non-survivors)
    CASE
      WHEN adm.hospital_expire_flag = 0 THEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)
      ELSE NULL
    END AS survivor_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt ON adm.subject_id = pt.subject_id
    -- Filter for ICH diagnoses (distinct hadm_id)
    INNER JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code IN ('430','431','4320','4321','4329'))
        OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
    ) diag ON adm.hadm_id = diag.hadm_id
    -- Check for ICU stays (distinct hadm_id)
    LEFT JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) icu ON adm.hadm_id = icu.hadm_id
  WHERE
    pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 69 AND 79
),

quintiles AS (
  SELECT
    -- Assign quintiles (1-5) based on age
    NTILE(5) OVER (ORDER BY age) AS quintile,
    *
  FROM cohort
)

SELECT
  quintile,
  COUNT(*) AS n,  -- Number of admissions
  ROUND(AVG(mortality_30d) * 100, 2) AS mortality_30d_pct,  -- 30-day mortality %
  ROUND(AVG(major_complication) * 100, 2) AS major_complication_pct,  -- Complication %
  -- Median LOS for survivors (ignores NULLs)
  APPROX_QUANTILES(survivor_los, 100)[OFFSET(50)] AS median_survivor_los
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
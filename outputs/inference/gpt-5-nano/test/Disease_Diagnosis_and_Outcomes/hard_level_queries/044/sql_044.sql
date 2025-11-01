WITH baseline AS (
  SELECT
    ROUND(100.0 * AVG(
      CASE
        WHEN p.dod IS NOT NULL
             AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) <= 30
        THEN 1 ELSE 0
      END
    ), 2) AS baseline_30d_mortality_pct
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Step 1: compute flags and outcomes for female 59-69 with cardiac arrest
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.anchor_age,
    -- 30-day mortality indicator
    CASE
      WHEN p.dod IS NOT NULL
           AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) <= 30
      THEN 1 ELSE 0
    END AS death_30,
    -- length of stay in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,

    -- Risk components (flags)
    -- CHF/heart disease (2 points)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
          ON di.icd_code = ddi.icd_code
         AND di.icd_version = ddi.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND di.subject_id = a.subject_id
          AND (ddi.long_title LIKE '%cardiac%' OR ddi.long_title LIKE '%myocardial%' OR di.icd_code LIKE 'I%')
      ) THEN 2 ELSE 0 END AS CHF_flag2,

    -- Chronic kidney disease (2 points)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
          ON di.icd_code = ddi.icd_code
         AND di.icd_version = ddi.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND di.subject_id = a.subject_id
          AND (ddi.long_title LIKE '%chronic kidney disease%' OR ddi.long_title LIKE '%kidney%')
      ) THEN 2 ELSE 0 END AS CKD_flag2,

    -- Diabetes (1 point)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
          ON di.icd_code = ddi.icd_code
         AND di.icd_version = ddi.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND di.subject_id = a.subject_id
          AND (ddi.long_title LIKE '%diab%' OR ddi.long_title LIKE '%diabetes%' OR di.icd_code LIKE '250%')
      ) THEN 1 ELSE 0 END AS Diabetes_flag1,

    -- Liver disease (1 point)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
          ON di.icd_code = ddi.icd_code
         AND di.icd_version = ddi.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND di.subject_id = a.subject_id
          AND (ddi.long_title LIKE '%liver%' OR ddi.long_title LIKE '%cirrhosis%')
      ) THEN 1 ELSE 0 END AS Liver_flag1,

    -- Cardiovascular complications indicator (admission-level)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diC
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiC
          ON diC.icd_code = ddiC.icd_code
         AND diC.icd_version = ddiC.icd_version
        WHERE diC.hadm_id = a.hadm_id
          AND diC.subject_id = a.subject_id
          AND (ddiC.long_title LIKE '%cardiac%' OR ddiC.long_title LIKE '%myocardial%' OR diC.icd_code LIKE 'I%')
      ) THEN 1 ELSE 0 END AS cardio_event,

    -- Neurological complications indicator (admission-level)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diN
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiN
          ON diN.icd_code = ddiN.icd_code
         AND diN.icd_version = ddiN.icd_version
        WHERE diN.hadm_id = a.hadm_id
          AND diN.subject_id = a.subject_id
          AND (ddiN.long_title LIKE '%stroke%' OR ddiN.long_title LIKE '%encephal%' OR ddiN.long_title LIKE '%intracranial%' OR diN.icd_code LIKE 'I63%')
      ) THEN 1 ELSE 0 END AS neuro_event

  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- Cardiac arrest filter
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
        ON di.icd_code = ddi.icd_code
       AND di.icd_version = ddi.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND di.subject_id = a.subject_id
        AND ddi.long_title LIKE '%cardiac arrest%'
    )
),

cohort_sql AS (
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY c.risk_score ASC) AS quartile
  FROM cohort c
),

medians AS (
  SELECT quartile,
         AVG(los_days) AS median_los_days
  FROM (
    SELECT quartile, los_days,
           ROW_NUMBER() OVER (PARTITION BY quartile ORDER BY los_days) AS rn,
           COUNT(*) OVER (PARTITION BY quartile) AS total
    FROM cohort_sql
  ) AS sub
  WHERE rn IN (FLOOR((total + 1) / 2), CEILING((total + 1) / 2))
  GROUP BY quartile
)

SELECT
  q.quartile,
  AVG(q.death_30) AS thirty_day_mortality_pct,
  AVG(q.cardio_event) AS cardio_complication_rate,
  AVG(q.neuro_event) AS neuro_complication_rate,
  m.median_los_days AS median_survivor_los_days,
  b.baseline_30d_mortality_pct
FROM cohort_sql q
JOIN medians m ON q.quartile = m.quartile
CROSS JOIN baseline b
GROUP BY q.quartile, m.median_los_days, b.baseline_30d_mortality_pct
ORDER BY q.quartile;
WITH
-- 1. ACS admissions based on ICD diagnosis titles
acs_admissions AS (
  SELECT DISTINCT di.subject_id,
                  di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
),

-- 2. Restrict to male patients age 80–90 with an ACS admission
cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_admissions acs
    ON a.subject_id = acs.subject_id
   AND a.hadm_id = acs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

-- 3. Identify hs‐TnT itemids
hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(category) LIKE '%troponin%'
),

-- 4. First hs‐TnT per admission
first_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS tnt_value,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hs_tnt_items hi
    ON le.itemid = hi.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM cohort)
    AND le.valuenum IS NOT NULL
)
,
first_tnt_per_adm AS (
  SELECT subject_id,
         hadm_id,
         tnt_value
  FROM first_tnt
  WHERE rn = 1
),

-- 5. Combine cohort with first Troponin and categorize
tnt_categorized AS (
  SELECT c.subject_id,
         c.hadm_id,
         c.los_days,
         f.tnt_value,
         CASE
           WHEN f.tnt_value < 14 THEN 'Normal'
           WHEN f.tnt_value BETWEEN 14 AND 52 THEN 'Borderline'
           WHEN f.tnt_value > 52 THEN 'Myocardial Injury'
           ELSE 'Unknown'
         END AS tnt_category
  FROM cohort c
  LEFT JOIN first_tnt_per_adm f
    ON c.hadm_id = f.hadm_id
)

-- 6. Final aggregation
SELECT
  tnt_category,
  COUNT(*) AS admission_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percent_of_cohort,
  ROUND(AVG(los_days), 1) AS mean_los_days
FROM tnt_categorized
GROUP BY tnt_category
ORDER BY
  CASE
    WHEN tnt_category = 'Normal' THEN 1
    WHEN tnt_category = 'Borderline' THEN 2
    WHEN tnt_category = 'Myocardial Injury' THEN 3
    ELSE 4
  END;
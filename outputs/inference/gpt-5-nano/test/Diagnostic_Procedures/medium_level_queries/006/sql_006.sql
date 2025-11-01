WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
admitted_cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.icustays` i
             WHERE i.hadm_id = a.hadm_id
               AND i.subject_id = a.subject_id
           ) THEN 'ICU'
           ELSE 'Non-ICU'
         END AS icu_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%septic shock%'
    )
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM (
    SELECT hadm_id, itemid
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    WHERE (LOWER(di.category) LIKE '%ultrasound%' OR LOWER(di.label) LIKE '%ultrasound%')
  )
  GROUP BY hadm_id
)
SELECT ac.icu_group,
       CASE
         WHEN ac.los_days BETWEEN 1 AND 4 THEN '1-4'
         WHEN ac.los_days BETWEEN 5 AND 8 THEN '5-8'
       END AS los_group,
       COUNT(DISTINCT ac.subject_id) AS patient_count,
       AVG(IFNULL(uc.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM admitted_cohort ac
LEFT JOIN ultrasound_counts uc
  ON ac.hadm_id = uc.hadm_id
WHERE ac.los_days BETWEEN 1 AND 8
GROUP BY ac.icu_group, los_group
ORDER BY ac.icu_group, los_group;
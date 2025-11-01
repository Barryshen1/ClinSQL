WITH acs_admissions AS (
  SELECT DISTINCT
         a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
          OR
          (di.icd_version = 9  AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'))
        )
),

ultrasound_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ultrasound%'
     OR LOWER(label) LIKE '%echocardiography%'
),

ultrasound_per_hadm AS (
  SELECT pe.hadm_id,
         COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN ultrasound_items AS ui
    ON pe.itemid = ui.itemid
  GROUP BY pe.hadm_id
)

SELECT t.los_group,
       COUNT(DISTINCT t.subject_id) AS patient_count,
       AVG(IFNULL(t.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM (
  SELECT a.hadm_id,
         a.subject_id,
         a.los_days,
         CASE
           WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
           WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
           ELSE NULL
         END AS los_group,
         u.ultrasound_count
  FROM acs_admissions AS a
  LEFT JOIN ultrasound_per_hadm AS u
    ON u.hadm_id = a.hadm_id
) AS t
WHERE t.los_group IS NOT NULL
GROUP BY t.los_group
ORDER BY t.los_group;
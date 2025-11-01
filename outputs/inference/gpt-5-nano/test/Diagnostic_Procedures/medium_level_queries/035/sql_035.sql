WITH eligible AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

-- 2) Identify AKI presence per admission (primary vs any AKI)
aki_flags AS (
  SELECT e.hadm_id,
         MAX(CASE
               WHEN di.seq_num = 1
                    AND ((di.icd_version = 9 AND di.icd_code LIKE '584%')
                         OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%'))
               THEN 1 ELSE 0 END) AS primary_aki_present,
         MAX(CASE
               WHEN ((di.icd_version = 9 AND di.icd_code LIKE '584%')
                     OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%'))
               THEN 1 ELSE 0 END) AS any_aki_present
  FROM eligible AS e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = e.subject_id
   AND di.hadm_id = e.hadm_id
  GROUP BY e.hadm_id
),

-- 3) Build AKI cohort with LOS
aki_cohort AS (
  SELECT a.hadm_id, a.subject_id,
         CASE
           WHEN af.primary_aki_present = 1 THEN 'Primary AKI'
           WHEN af.any_aki_present = 1 THEN 'Secondary AKI'
         END AS aki_group,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = e.hadm_id
   AND a.subject_id = e.subject_id
  JOIN aki_flags AS af
    ON af.hadm_id = a.hadm_id
  WHERE af.primary_aki_present = 1 OR af.any_aki_present = 1
),

-- 4) Bucket LOS and keep only 1-4 or 5-7 days
cohort AS (
  SELECT hadm_id, subject_id, aki_group, los_days,
         CASE
           WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
           WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
         END AS los_bucket
  FROM aki_cohort
  WHERE los_days BETWEEN 1 AND 7
    AND aki_group IS NOT NULL
),

-- 5) MRI/CT counts per admission from ICU procedureevents
mri_counts AS (
  SELECT pe.hadm_id, COUNT(*) AS mri_cts
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = pe.itemid
  JOIN cohort AS c
    ON c.hadm_id = pe.hadm_id
  WHERE LOWER(di.label) LIKE '%mri%'
     OR LOWER(di.label) LIKE '%ct%'
  GROUP BY pe.hadm_id
)

-- 6) Final aggregation by AKI group and LOS bucket
SELECT c.aki_group,
       c.los_bucket,
       COUNT(DISTINCT c.hadm_id) AS n_admissions,
       COUNT(DISTINCT c.subject_id) AS n_patients,
       IFNULL(AVG(m.mri_cts), 0) AS mean_mri_cts_per_admission
FROM cohort AS c
LEFT JOIN mri_counts AS m
  ON m.hadm_id = c.hadm_id
GROUP BY c.aki_group, c.los_bucket
ORDER BY c.aki_group, c.los_bucket;
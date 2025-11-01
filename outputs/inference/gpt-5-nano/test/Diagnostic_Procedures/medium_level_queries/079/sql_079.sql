WITH lgib_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN MAX(CASE
                 WHEN di.seq_num = 1
                      AND LOWER(dd.long_title) LIKE '%lower%'
                      AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
                 THEN 1 ELSE 0 END) = 1
      THEN 'primary'
      WHEN MAX(CASE
                 WHEN di.seq_num > 1
                      AND LOWER(dd.long_title) LIKE '%lower%'
                      AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
                 THEN 1 ELSE 0 END) = 1
      THEN 'secondary'
      ELSE NULL
    END AS lgib_class
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
  GROUP BY a.hadm_id, a.admittime, a.dischtime
  HAVING (MAX(CASE
                WHEN di.seq_num = 1
                     AND LOWER(dd.long_title) LIKE '%lower%'
                     AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
                THEN 1 ELSE 0 END) = 1)
     OR (MAX(CASE
                WHEN di.seq_num > 1
                     AND LOWER(dd.long_title) LIKE '%lower%'
                     AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
                THEN 1 ELSE 0 END) = 1)
),

imaging_by_hadm AS (
  SELECT
    icu.hadm_id,
    COUNT(DISTINCT ce.charttime) AS imaging_per_hadm
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.category) LIKE '%radiology%'
         OR LOWER(di.label) LIKE '%ct%'
         OR LOWER(di.label) LIKE '%x-ray%'
         OR LOWER(di.label) LIKE '%radiograph%')
  GROUP BY icu.hadm_id
),

-- 3) Combine LGIB admissions with imaging counts and LOS groups
agg AS (
  SELECT
    la.hadm_id,
    la.lgib_class,
    CASE
      WHEN DATE_DIFF(DATE(la.dischtime), DATE(la.admittime), DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(la.dischtime), DATE(la.admittime), DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_group,
    COALESCE(ib.imaging_per_hadm, 0) AS imaging_count
  FROM lgib_admissions la
  LEFT JOIN imaging_by_hadm ib
    ON la.hadm_id = ib.hadm_id
  WHERE la.lgib_class IS NOT NULL
)

SELECT
  lgib_class,
  stay_group,
  AVG(imaging_count) AS mean_radiography_cts_per_admission
FROM agg
WHERE stay_group IS NOT NULL
GROUP BY lgib_class, stay_group
ORDER BY lgib_class, stay_group;
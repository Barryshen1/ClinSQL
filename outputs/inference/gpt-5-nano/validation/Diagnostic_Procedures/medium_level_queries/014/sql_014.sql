WITH acs_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Primary vs secondary ACS classification
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di1
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd1
          ON di1.icd_code = dd1.icd_code
         AND di1.icd_version = dd1.icd_version
        WHERE di1.subject_id = a.subject_id
          AND di1.hadm_id = a.hadm_id
          AND di1.seq_num = 1
          AND LOWER(dd1.long_title) LIKE '%acute%coronary%'
      ) THEN 'primary'
      ELSE 'secondary'
    END AS acs_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    -- age in the anchor framework
    AND p.anchor_age BETWEEN 83 AND 93
    -- require ACS to be present for the admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_sub
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_sub
        ON di_sub.icd_code = dd_sub.icd_code
       AND di_sub.icd_version = dd_sub.icd_version
      WHERE di_sub.subject_id = a.subject_id
        AND di_sub.hadm_id = a.hadm_id
        AND LOWER(dd_sub.long_title) LIKE '%acute%coronary%'
    )
    AND a.dischtime IS NOT NULL
),

-- 2) Per-admission ultrasound counts (including zero counts via LEFT JOIN)
per_admission AS (
  SELECT
    a.hadm_id,
    a.acs_group,
    -- LOS: 1-4 days or 5-7 days
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS stay_group,
    -- ultrasound_count: number of ultrasound-related chart items in ICU chartevents for this hadm
    SUM(CASE WHEN di.label IS NOT NULL THEN 1 ELSE 0 END) AS ultrasound_count
  FROM acs_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
   AND LOWER(di.label) LIKE '%ultrasound%'
  GROUP BY a.hadm_id, a.acs_group,
           CASE
             WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
             WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 5 AND 7 THEN '5-7'
             ELSE NULL
           END
)

-- 3) Final aggregation: mean, min, max ultrasound counts per group
SELECT
  acs_group,
  stay_group,
  ROUND(AVG(ultrasound_count), 4) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM per_admission
WHERE stay_group IS NOT NULL
GROUP BY acs_group, stay_group
ORDER BY acs_group, stay_group;
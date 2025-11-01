WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN a.admission_type = 'EMERGENCY' THEN 'ED'
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE a.admission_type
    END AS admission_type_label
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admission_type IN ('EMERGENCY','ELECTIVE')
),

-- Ultrasound-related procedure events within admission window
ultra_events AS (
  SELECT pe.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON pe.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%ultrasound%'
         OR LOWER(di.label) LIKE '%echocardiography%')
  GROUP BY pe.hadm_id
),

-- Attach counts to cohort and carry a zero for admissions with no ultrasounds
cohort_with_counts AS (
  SELECT c.hadm_id,
         c.admittime,
         c.dischtime,
         c.admission_type_label,
         COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM cohort AS c
  LEFT JOIN ultra_events AS u
    ON c.hadm_id = u.hadm_id
),

-- Compute stay_group for 1-3d vs 4-7d stays
cohort_grouped AS (
  SELECT
    CASE
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3d'
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7d'
      ELSE 'other'
    END AS stay_group,
    admission_type_label,
    ultrasound_count
  FROM cohort_with_counts
)

SELECT
  stay_group,
  admission_type_label,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM cohort_grouped
WHERE stay_group IN ('1-3d','4-7d')
GROUP BY stay_group, admission_type_label
ORDER BY stay_group, admission_type_label;
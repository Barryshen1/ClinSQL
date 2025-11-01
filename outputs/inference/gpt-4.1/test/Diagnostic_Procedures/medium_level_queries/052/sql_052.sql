WITH female_73_83 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 73 AND 83
),

admission_stay_groups AS (
  SELECT
    subject_id,
    hadm_id,
    admission_type,
    admittime,
    dischtime,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_group
  FROM
    female_73_83
),

ultrasound_procedures AS (
  SELECT
    dp.icd_code,
    dp.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%'
    OR LOWER(dp.long_title) LIKE '%echocardiograph%'
),

ultrasound_counts AS (
  SELECT
    ag.subject_id,
    ag.hadm_id,
    ag.admission_type,
    ag.stay_group,
    COUNT(DISTINCT pr.seq_num) AS ultrasound_count
  FROM
    admission_stay_groups ag
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON ag.subject_id = pr.subject_id
      AND ag.hadm_id = pr.hadm_id
    INNER JOIN ultrasound_procedures up
      ON pr.icd_code = up.icd_code AND pr.icd_version = up.icd_version
  WHERE
    ag.stay_group IS NOT NULL
    AND (UPPER(ag.admission_type) LIKE '%EMERGENCY%' OR UPPER(ag.admission_type) LIKE '%ELECTIVE%')
  GROUP BY
    ag.subject_id, ag.hadm_id, ag.admission_type, ag.stay_group
),

final_stats AS (
  SELECT
    CASE
      WHEN UPPER(admission_type) LIKE '%EMERGENCY%' THEN 'ED'
      WHEN UPPER(admission_type) LIKE '%ELECTIVE%' THEN 'Elective'
      ELSE 'Other'
    END AS admission_type_group,
    stay_group,
    AVG(ultrasound_count) AS mean_ultrasounds_per_admission,
    MIN(ultrasound_count) AS min_ultrasounds_per_admission,
    MAX(ultrasound_count) AS max_ultrasounds_per_admission,
    COUNT(*) AS num_admissions
  FROM
    ultrasound_counts
  GROUP BY
    admission_type_group, stay_group
)

SELECT
  admission_type_group,
  stay_group,
  mean_ultrasounds_per_admission,
  min_ultrasounds_per_admission,
  max_ultrasounds_per_admission,
  num_admissions
FROM
  final_stats
ORDER BY
  admission_type_group, stay_group;
WITH hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT p.subject_id, icu.hadm_id
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON icu.hadm_id = proc.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d_proc
    ON proc.icd_code = d_proc.icd_code
    AND proc.icd_version = d_proc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(d_proc.long_title) LIKE '%hemorrhage%'
    AND LOWER(d_proc.long_title) LIKE '%stroke%'
),

ultrasound_itemids AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE linksto = 'procedureevents'
    AND LOWER(label) LIKE '%ultrasound%'
),

icu_ultrasound_counts AS (
  SELECT
    icu.hadm_id,
    SUM(CASE WHEN u.itemid IS NOT NULL THEN 1 ELSE 0 END) AS ultrasound_count
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN hemorrhagic_stroke_admissions hsa
    ON icu.hadm_id = hsa.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents u
    ON icu.stay_id = u.stay_id
    AND u.itemid IN (SELECT itemid FROM ultrasound_itemids)
    AND u.starttime >= icu.intime
    AND u.starttime <= icu.outtime
  GROUP BY icu.hadm_id
),

admission_stay_duration AS (
  SELECT
    hadm_id,
    SUM(los) AS total_los
  FROM physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY hadm_id
),

grouped_stats AS (
  SELECT
    CASE
      WHEN los.total_los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los.total_los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS stay_group,
    u.ultrasound_count
  FROM icu_ultrasound_counts u
  JOIN admission_stay_duration los
    ON u.hadm_id = los.hadm_id
  WHERE los.total_los BETWEEN 1 AND 7
)

SELECT
  stay_group,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM grouped_stats
GROUP BY stay_group
ORDER BY stay_group;
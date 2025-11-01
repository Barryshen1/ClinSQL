WITH acs_flags AS (
  SELECT di.hadm_id, di.subject_id,
         MAX(CASE
               WHEN di.seq_num = 1
                    AND (dd.long_title LIKE '%acute coronary%' 
                         OR dd.long_title LIKE '%myocardial infarction%' 
                         OR dd.long_title LIKE '%unstable angina%' 
                         OR dd.long_title LIKE '%acute coronary syndrome%')
               THEN 1 ELSE 0 END) AS primary_acs,
         MAX(CASE
               WHEN (dd.long_title LIKE '%acute coronary%' 
                     OR dd.long_title LIKE '%myocardial infarction%' 
                     OR dd.long_title LIKE '%unstable angina%' 
                     OR dd.long_title LIKE '%acute coronary syndrome%')
               THEN 1 ELSE 0 END) AS any_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id, di.subject_id
),
ultrasound_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE REGEXP_CONTAINS(LOWER(label), 'ultrasound|echo')
),
per_admission AS (
  SELECT a.hadm_id, a.subject_id,
         CASE
           WHEN af.primary_acs = 1 THEN 'primary'
           WHEN af.any_acs = 1 THEN 'secondary'
           ELSE NULL
         END AS acs_type,
         CASE
           WHEN (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) >= 1
                AND (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) <= 4 THEN '1-4'
           WHEN (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) >= 5
                AND (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) <= 7 THEN '5-7'
           ELSE NULL
         END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN acs_flags af
    ON af.hadm_id = a.hadm_id
   AND af.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (af.primary_acs = 1 OR af.any_acs = 1)
),
ultrasound_events AS (
  SELECT pe.hadm_id, pe.subject_id, pe.acs_type, pe.los_group,
         COUNT(DISTINCT ce.charttime) AS ultrasound_count
  FROM per_admission pe
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pe.subject_id = i.subject_id
   AND pe.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN ultrasound_items ui
    ON ce.itemid = ui.itemid
  WHERE ce.charttime BETWEEN i.intime AND i.outtime
  GROUP BY pe.hadm_id, pe.subject_id, pe.acs_type, pe.los_group
)
SELECT los_group,
       acs_type,
       q[OFFSET(1)] AS p25,
       q[OFFSET(2)] AS p50,
       q[OFFSET(3)] AS p75
FROM (
  SELECT los_group, acs_type, APPROX_QUANTILES(ultrasound_count, 4) AS q
  FROM ultrasound_events
  GROUP BY los_group, acs_type
) t
ORDER BY los_group, acs_type;
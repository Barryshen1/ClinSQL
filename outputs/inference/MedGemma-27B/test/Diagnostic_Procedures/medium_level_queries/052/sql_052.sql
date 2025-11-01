WITH PatientAgeGroup AS (
  SELECT
    subject_id,
    CASE
      WHEN anchor_age BETWEEN 73 AND 83 THEN '73-83'
      ELSE 'Other'
    END AS age_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    p.age_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientAgeGroup AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.age_group = '73-83'
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
),
UltrasoundEvents AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT pe.itemid) AS ultrasound_count
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON a.hadm_id = pe.hadm_id
  WHERE
    pe.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE '%ultrasound%' OR label LIKE '%echocardiography%'
    )
  GROUP BY
    a.hadm_id
),
StayDuration AS (
  SELECT
    hadm_id,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS stay_duration_group
  FROM
    AdmissionInfo
)
SELECT
  ai.admission_type,
  sd.stay_duration_group,
  AVG(ue.ultrasound_count) AS mean_ultrasounds,
  MIN(ue.ultrasound_count) AS min_ultrasounds,
  MAX(ue.ultrasound_count) AS max_ultrasounds
FROM
  AdmissionInfo AS ai
JOIN
  StayDuration AS sd
  ON ai.hadm_id = sd.hadm_id
JOIN
  UltrasoundEvents AS ue
  ON ai.hadm_id = ue.hadm_id
WHERE
  sd.stay_duration_group IN ('1-3 days', '4-7 days')
GROUP BY
  ai.admission_type,
  sd.stay_duration_group
ORDER BY
  ai.admission_type,
  sd.stay_duration_group;
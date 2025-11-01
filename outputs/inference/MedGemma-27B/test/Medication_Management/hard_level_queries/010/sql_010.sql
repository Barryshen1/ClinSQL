WITH PatientAge AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN anchor_age BETWEEN 61 AND 71 THEN 1
      ELSE 0
    END AS is_target_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), MedicationComplexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT e.emar_id) AS medication_complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON e.hadm_id = a.hadm_id
    INNER JOIN PatientAge AS pa
      ON e.subject_id = pa.subject_id AND e.hadm_id = pa.hadm_id
  WHERE
    pa.is_target_age = 1
    AND e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY
    p.subject_id,
    p.hadm_id
), Quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    medication_complexity_score,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS complexity_quintile
  FROM
    MedicationComplexity
), AdmissionData AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.complexity_quintile,
    q.medication_complexity_score,
    a.los,
    a.hospital_expire_flag,
    a.dischtime
  FROM
    Quintiles AS q
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON q.hadm_id = a.hadm_id
), ReadmissionData AS (
  SELECT
    ad.subject_id,
    ad.hadm_id,
    ad.dischtime,
    MIN(a2.admittime) AS readmission_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      ON ad.subject_id = a2.subject_id
      AND a2.admittime > ad.dischtime
  WHERE
    ad.hadm_id IN (
      SELECT
        hadm_id
      FROM
        AdmissionData
    )
  GROUP BY
    ad.subject_id,
    ad.hadm_id,
    ad.dischtime
)
SELECT
  complexity_quintile,
  COUNT(DISTINCT subject_id) AS number_of_patients,
  AVG(medication_complexity_score) AS mean_complexity_score,
  AVG(los) AS average_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(CASE WHEN readmission_time IS NOT NULL THEN 1 ELSE 0 END) AS thirty_day_readmission_rate
FROM
  AdmissionData AS ad
  LEFT JOIN ReadmissionData AS rd
    ON ad.subject_id = rd.subject_id AND ad.hadm_id = rd.hadm_id
GROUP BY
  complexity_quintile
ORDER BY
  complexity_quintile;
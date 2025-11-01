WITH Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    p.gender,
    p.anchor_age,
    di.icd_code,
    d.long_title AS diagnosis_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'SNF'
    AND di.icd_code LIKE 'N39%' -- UTI codes;
    AND a.insurance = 'Medicare' -- Added Medicare filter
)
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN readmitted = TRUE THEN subject_id END) AS readmitted_patients,
  (COUNT(DISTINCT CASE WHEN readmitted = TRUE THEN subject_id END) / COUNT(DISTINCT subject_id)) * 100 AS readmission_rate,
  MEDIAN(CASE WHEN readmitted = TRUE THEN los THEN NULL ELSE los END) AS median_los_non_readmitted,
  MEDIAN(CASE WHEN readmitted = TRUE THEN los ELSE NULL END) AS median_los_readmitted,
  COUNT(DISTINCT CASE WHEN los > 6 THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS percent_stays_gt_6_days
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.los,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN TRUE ELSE FALSE END AS readmitted
  FROM Cohort c
);
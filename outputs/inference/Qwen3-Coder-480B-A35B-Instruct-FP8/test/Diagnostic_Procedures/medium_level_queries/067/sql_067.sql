WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 7
    AND LOWER(d.long_title) LIKE '%acute coronary%'
),

ultrasound_counts AS (
  SELECT
    af.hadm_id,
    af.los_days,
    af.diagnosis_type,
    COUNT(*) AS ultrasound_count
  FROM
    admissions_filtered af
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON af.hadm_id = pi.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%' OR LOWER(dp.long_title) LIKE '%echo%'
  GROUP BY
    af.hadm_id, af.los_days, af.diagnosis_type
),

stratified_data AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    diagnosis_type,
    ultrasound_count
  FROM
    ultrasound_counts
)

SELECT
  los_group,
  diagnosis_type,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75
FROM
  stratified_data
GROUP BY
  los_group,
  diagnosis_type
ORDER BY
  los_group,
  diagnosis_type;
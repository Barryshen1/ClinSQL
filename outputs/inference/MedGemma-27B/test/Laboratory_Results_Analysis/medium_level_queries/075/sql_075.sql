WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 41 AND 51
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%chest pain%' OR LOWER(d.long_title) LIKE '%ami%'
), TroponinEvents AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_unit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
), FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime,
    valuenum AS troponin_value,
    valueuom AS troponin_unit
  FROM
    TroponinEvents
  GROUP BY
    subject_id,
    hadm_id
)
SELECT
  CASE
    WHEN ft.troponin_value < 0.01 THEN 'normal'
    WHEN ft.troponin_value BETWEEN 0.01 AND 0.1 THEN 'borderline'
    ELSE 'elevated'
  END AS troponin_category,
  COUNT(DISTINCT ft.subject_id) AS patient_count,
  COUNT(DISTINCT ft.subject_id) * 100.0 / COUNT(DISTINCT ft.subject_id) AS percentage,
  AVG(ft.troponin_value) AS mean_troponin,
  APPROX_QUANTILES(ft.troponin_value, 4)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(ft.troponin_value, 4)[OFFSET(0)] AS iqr_25,
  APPROX_QUANTILES(ft.troponin_value, 4)[OFFSET(2)] AS iqr_75
FROM
  FirstTroponin AS ft
JOIN
  AdmissionInfo AS ai
  ON ft.hadm_id = ai.hadm_id
JOIN
  PatientInfo AS pi
  ON ft.subject_id = pi.subject_id
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
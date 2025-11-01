WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 79 AND 89
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%acute coronary syndrome%' OR di.long_title LIKE '%myocardial infarction%'
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_t_value,
    l.valueuom AS troponin_t_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T'
), FirstTroponin AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.charttime,
    li.troponin_t_value,
    li.troponin_t_uom
  FROM
    LabInfo AS li
  JOIN
    (
      SELECT
        subject_id,
        hadm_id,
        MIN(charttime) AS min_charttime
      FROM
        LabInfo
      GROUP BY
        subject_id,
        hadm_id
    ) AS first_time
    ON li.subject_id = first_time.subject_id AND li.hadm_id = first_time.hadm_id AND li.charttime = first_time.min_charttime
), TroponinCategory AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.troponin_t_value,
    CASE
      WHEN ft.troponin_t_value < 0.01 THEN 'normal'
      WHEN ft.troponin_t_value BETWEEN 0.01 AND 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM
    FirstTroponin AS ft
)
SELECT
  tc.troponin_category,
  COUNT(tc.subject_id) AS count,
  COUNT(tc.subject_id) * 100.0 / SUM(COUNT(tc.subject_id)) OVER () AS percentage,
  AVG(tc.troponin_t_value) AS avg_troponin,
  MEDIAN(tc.troponin_t_value) AS median_troponin,
  PERCENTILE_CONT(tc.troponin_t_value, 0.25) AS iqr_25,
  PERCENTILE_CONT(tc.troponin_t_value, 0.75) AS iqr_75
FROM
  TroponinCategory AS tc
GROUP BY
  tc.troponin_category
ORDER BY
  tc.troponin_category;
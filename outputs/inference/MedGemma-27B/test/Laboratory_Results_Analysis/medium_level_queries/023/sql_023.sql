WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 72
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
    AND d.long_title LIKE '%acute coronary syndrome%'
), TroponinInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.valuenum AS troponin_value,
    l.valueuom AS troponin_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l ON a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T'
    AND l.charttime >= a.admittime
    AND l.charttime < a.dischtime
)
SELECT
  CASE
    WHEN t.troponin_value <= 0.04
    THEN '≤0.04 normal'
    WHEN t.troponin_value > 0.04 AND t.troponin_value <= 0.1
    THEN '>0.04–0.1 borderline'
    ELSE '>0.1 elevated'
  END AS troponin_category,
  COUNT(DISTINCT a.hadm_id) AS count_admissions,
  COUNT(DISTINCT a.hadm_id) * 100.0 / SUM(COUNT(DISTINCT a.hadm_id)) OVER () AS percent_admissions,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT a.hadm_id) AS mortality_rate
FROM
  AdmissionInfo AS a
JOIN
  PatientInfo AS p ON a.subject_id = p.subject_id
JOIN
  TroponinInfo AS t ON a.hadm_id = t.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
GROUP BY
  troponin_category
ORDER BY
  CASE
    WHEN troponin_category = '≤0.04 normal' THEN 1
    WHEN troponin_category = '>0.04–0.1 borderline' THEN 2
    ELSE 3
  END;
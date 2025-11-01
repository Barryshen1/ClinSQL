WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), LabInfo AS (
  SELECT
    labevent_id,
    subject_id,
    hadm_id,
    charttime,
    itemid,
    value,
    valuenum,
    valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
), LabItemInfo AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    label LIKE 'Troponin T%'
), DiagnosisInfo AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = '9'
    AND icd_code IN ('410', '411', '414', '427', '428')
), HospitalLOS AS (
  SELECT
    hadm_id,
    subject_id,
    TIMESTAMP_DIFF(dischtime, admitime, HOUR) AS hospital_los
  FROM
    AdmissionInfo
)
SELECT
  CASE
    WHEN lab.valuenum IS NULL THEN 'Unknown'
    WHEN lab.valuenum < 0.01 THEN 'Normal'
    WHEN lab.valuenum BETWEEN 0.01 AND 0.1 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_category,
  COUNT(DISTINCT hadm_id) AS count,
  COUNT(DISTINCT hadm_id) * 100.0 / SUM(COUNT(DISTINCT hadm_id)) OVER () AS percentage,
  AVG(hosp_los.hospital_los) AS avg_hospital_los
FROM
  PatientInfo AS p
INNER JOIN
  AdmissionInfo AS adm ON p.subject_id = adm.subject_id
INNER JOIN
  DiagnosisInfo AS diag ON p.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
INNER JOIN
  LabInfo AS lab ON p.subject_id = lab.subject_id AND adm.hadm_id = lab.hadm_id
INNER JOIN
  LabItemInfo AS lab_item ON lab.itemid = lab_item.itemid
INNER JOIN
  HospitalLOS AS hosp_los ON adm.hadm_id = hosp_los.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND lab.charttime BETWEEN adm.admittime AND adm.dischtime
  AND lab.charttime = (
    SELECT
      MIN(charttime)
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` -- Added dataset qualification
    WHERE
      subject_id = lab.subject_id
      AND hadm_id = lab.hadm_id
      AND itemid = lab.itemid
  )
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
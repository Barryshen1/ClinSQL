WITH patient_info AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
),
primary_diagnosis AS (
  SELECT d.subject_id, d.hadm_id, d.icd_code, d.icd_version, dicd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1
),
hemorrhagic_stroke_patients AS (
  SELECT pi.subject_id, pi.hadm_id, pi.los
  FROM patient_info pi
  INNER JOIN primary_diagnosis pd
  ON pi.subject_id = pd.subject_id AND pi.hadm_id = pd.hadm_id
  WHERE (pd.icd_version = 9 AND pd.icd_code = '431')
     OR (pd.icd_version = 10 AND pd.icd_code LIKE 'I61%')
)
SELECT STDDEV(LOS) AS sd_los
FROM hemorrhagic_stroke_patients;
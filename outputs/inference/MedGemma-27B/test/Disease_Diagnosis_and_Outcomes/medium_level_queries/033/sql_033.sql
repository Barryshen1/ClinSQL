WITH PatientComorbidity AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_version = 9 -- Assuming ICD-9 for comorbidity count, adjust if needed
    AND d.seq_num = 1 -- Consider only primary diagnoses for comorbidity count
  GROUP BY
    p.subject_id,
    p.gender,
    p.anchor_age
),
ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.hadm_id = i.hadm_id
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.discharge_location,
    a.admission_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),
PostOpComplication AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    p.icd_version = 9
    AND p.icd_code LIKE '0%' -- Assuming major surgery codes start with 0 in ICD-9
    AND a.admission_type = 'EMERGENCY' -- Assuming postoperative complications often follow emergency admissions
)
SELECT
  pc.icu_status,
  CASE
    WHEN pc.los <= 5 THEN '≤5'
    ELSE '>5'
  END AS los_category,
  CASE
    WHEN pc.comorbidity_count = 0 THEN '0-1'
    WHEN pc.comorbidity_count = 1 THEN '0-1'
    WHEN pc.comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_bin,
  COUNT(DISTINCT pc.subject_id) AS N,
  AVG(CASE WHEN pc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_percent,
  AVG(pc.comorbidity_count) AS average_comorbidity_count
FROM PatientComorbidity AS pc
JOIN ICUStayInfo AS i
  ON pc.subject_id = i.subject_id
JOIN AdmissionInfo AS a
  ON pc.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
JOIN PostOpComplication AS po
  ON pc.subject_id = po.subject_id AND i.hadm_id = po.hadm_id
WHERE
  pc.gender = 'M'
  AND pc.anchor_age BETWEEN 82 AND 92
  AND pc.comorbidity_count > 0 -- Exclude patients with 0 comorbidities
  AND a.hospital_expire_flag IS NOT NULL -- Ensure mortality flag is recorded
GROUP BY
  pc.icu_status,
  los_category,
  comorbidity_bin
ORDER BY
  pc.icu_status,
  los_category,
  comorbidity_;
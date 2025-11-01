WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
),
ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
TroponinEvents AS (
  SELECT
    t.subject_id,
    t.stay_id,
    t.charttime,
    t.valuenum AS troponin_value,
    t.valueuom AS troponin_uom
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS t
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON t.itemid = d.itemid
  WHERE
    t.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    ) AND d.label LIKE 'Troponin T%'
),
DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    ) AND di.long_title LIKE '%chest pain%'
    OR di.long_title LIKE '%myocardial infarction%'
    OR di.long_title LIKE '%AMI%'
),
HighTroponinEvents AS (
  SELECT
    te.subject_id,
    te.stay_id,
    te.charttime,
    te.troponin_value
  FROM TroponinEvents AS te
  WHERE
    te.troponin_uom = 'ng/mL'
    AND te.troponin_value > 0.01 -- Assuming 99th percentile is around 0.01 ng/mL
)
SELECT
  COUNT(DISTINCT pi.subject_id) AS N,
  AVG(pi.age) AS mean_age,
  AVG(icu.los) AS mean_los,
  AVG(hte.troponin_value) AS mean_high_troponin,
  MIN(hte.troponin_value) AS min_high_troponin,
  MAX(hte.troponin_value) AS max_high_troponin
FROM PatientInfo AS pi
LEFT JOIN ICUStayInfo AS icu
  ON pi.subject_id = icu.subject_id
LEFT JOIN HighTroponinEvents AS hte
  ON pi.subject_id = hte.subject_id AND icu.stay_id = hte.stay_id
LEFT JOIN DiagnosisInfo AS di
  ON pi.subject_id = di.subject_id
WHERE
  di.icd_code IS NOT NULL
GROUP BY
  pi.subject_id;
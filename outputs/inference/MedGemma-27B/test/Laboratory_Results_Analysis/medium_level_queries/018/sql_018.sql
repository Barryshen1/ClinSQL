WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
),
ACSAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND a.admission_type = 'EMERGENCY'
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code IN ('410', '411', '413', '414') -- ACS ICD-10 codes
    )
),
TroponinEvents AS (
  SELECT
    te.subject_id,
    te.hadm_id,
    te.charttime,
    te.valuenum AS troponin_value,
    te.valueuom AS troponin_uom
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS te
  WHERE
    te.subject_id IN (
      SELECT
        subject_id
      FROM
        ACSAdmissions
    )
    AND te.itemid = 50178 -- Troponin T itemid
),
TroponinCategories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN troponin_value < 0.01 THEN 'normal'
      WHEN troponin_value BETWEEN 0.01 AND 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM
    TroponinEvents
  WHERE
    troponin_uom = 'ng/mL'
    AND troponin_value IS NOT NULL
),
HospitalLOS AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.admittime,
    (
      TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24
    ) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        ACSAdmissions
    )
)
SELECT
  tc.troponin_category,
  COUNT(DISTINCT tc.subject_id) AS patient_count,
  COUNT(DISTINCT tc.hadm_id) AS admission_count,
  AVG(h.los) AS mean_los
FROM
  TroponinCategories AS tc
LEFT JOIN
  HospitalLOS AS h
  ON tc.subject_id = h.subject_id AND tc.hadm_id = h.hadm_id
GROUP BY
  tc.troponin_category
ORDER BY
  tc.troponin_category;
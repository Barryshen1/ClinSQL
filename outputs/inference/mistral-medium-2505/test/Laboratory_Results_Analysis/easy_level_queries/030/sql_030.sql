WITH acs_patients AS (
  -- Identify male patients with ACS diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON a.icd_code = d.icd_code AND a.icd_version = d.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- ACS ICD codes (ICD-9 and ICD-10)
    (a.icd_code LIKE '410.%' OR a.icd_code LIKE 'I20%' OR a.icd_code LIKE 'I21%' OR a.icd_code LIKE 'I22%' OR a.icd_code LIKE 'I23%' OR a.icd_code LIKE 'I24%')
    AND p.gender = 'M'
),

troponin_measurements AS (
  -- Get all troponin measurements for these patients
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    di.label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    -- Common troponin itemids
    l.itemid IN (50912, 50931)  -- Troponin I and Troponin T
    AND l.valuenum IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM acs_patients ap
      WHERE l.subject_id = ap.subject_id AND l.hadm_id = ap.hadm_id
    )
)

-- Calculate minimum troponin per patient
SELECT
  t.subject_id,
  p.gender,
  p.anchor_age,
  MIN(t.valuenum) AS min_troponin,
  t.label AS troponin_type
FROM
  troponin_measurements t
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON t.subject_id = p.subject_id
GROUP BY
  t.subject_id, p.gender, p.anchor_age, t.label
ORDER BY
  min_troponin;
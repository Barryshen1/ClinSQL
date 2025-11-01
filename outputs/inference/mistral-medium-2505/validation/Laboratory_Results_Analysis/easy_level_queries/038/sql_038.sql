WITH stroke_admissions AS (
  -- Get male admissions with ischemic stroke diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    -- Calculate age at admission (approximate)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    -- Ischemic stroke ICD codes (ICD-10: I63.*, ICD-9: 434.*)
    AND (d.icd_code LIKE 'I63%' OR d.icd_code LIKE '434%')
),

hemoglobin_measurements AS (
  -- Get hemoglobin measurements within 24 hours of admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hemoglobin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  JOIN
    stroke_admissions sa ON l.subject_id = sa.subject_id AND l.hadm_id = sa.hadm_id
  WHERE
    -- Hemoglobin itemid (example: 50811 for hemoglobin in MIMIC-IV)
    dl.label = 'Hemoglobin'
    -- Within 24 hours of admission
    AND l.charttime BETWEEN sa.admittime AND TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
)

-- Get the minimum hemoglobin value per admission
SELECT
  sa.subject_id,
  sa.hadm_id,
  MIN(hm.hemoglobin_value) AS min_hemoglobin_within_24h
FROM
  stroke_admissions sa
JOIN
  hemoglobin_measurements hm ON sa.subject_id = hm.subject_id AND sa.hadm_id = hm.hadm_id
GROUP BY
  sa.subject_id, sa.hadm_id
ORDER BY
  min_hemoglobin_within_24h;
WITH filtered_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE 
    pat.gender = 'F'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN (
        '531.00', '531.01', '531.10', '531.11', '531.20', '531.21', '531.30', '531.31', '531.40', '531.41', '531.50', '531.51', '531.60', '531.61',
        '532.00', '532.01', '532.10', '532.11', '532.20', '532.21', '532.30', '532.31', '532.40', '532.41', '532.50', '532.51', '532.60', '532.61',
        '533.00', '533.01', '533.10', '533.11', '533.20', '533.21', '533.30', '533.31', '533.40', '533.41', '533.50', '533.51', '533.60', '533.61',
        '534.00', '534.01', '534.10', '534.11', '534.20', '534.21', '534.30', '534.31', '534.40', '534.41', '534.50', '534.51', '534.60', '534.61',
        '456.0', '456.1', '456.20', '456.21'
      ))
      OR
      (diag.icd_version = 10 AND diag.icd_code IN (
        'K25.0', 'K25.1', 'K25.2', 'K25.3', 'K25.4', 'K25.5', 'K25.6',
        'K26.0', 'K26.1', 'K26.2', 'K26.3', 'K26.4', 'K26.5', 'K26.6',
        'K27.0', 'K27.1', 'K27.2', 'K27.3', 'K27.4', 'K27.5', 'K27.6',
        'K28.0', 'K28.1', 'K28.2', 'K28.3', 'K28.4', 'K28.5', 'K28.6',
        'I85.0', 'I85.10', 'I85.11',
        'K92.0', 'K92.1', 'K92.2'
      ))
    )
)
SELECT MAX(los_days) AS max_los_days
FROM filtered_admissions
WHERE age_at_admit BETWEEN 49 AND 59;
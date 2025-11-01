SELECT
  MIN(pct.avg_cr) AS min_24h_avg_serum_creatinine
FROM (
  -- Compute 24h average creatinine per admission
  SELECT
    a.hadm_id,
    AVG(le.valuenum) AS avg_cr
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Only female patients
    AND p.gender = 'F'
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
    -- Pneumonia diagnoses
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
    -- Join creatinine lab events within first 24h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
      AND LOWER(di.label) LIKE '%creatinine%'
  WHERE
    le.valuenum IS NOT NULL
  GROUP BY
    a.hadm_id
) AS pct;
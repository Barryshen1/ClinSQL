WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 74
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    -- Heart failure diagnosis exists for this admission
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON d.icd_code = dicd.icd_code
          AND d.icd_version = dicd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR UPPER(dicd.long_title) LIKE '%HEART FAILURE%'
        )
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

diagnostic_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS num_diag
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    d.short_description IN ('Imaging', 'ECG', 'EEG', 'PFT')
  GROUP BY
    h.hadm_id
)

SELECT
  CASE
    WHEN ha.los BETWEEN 1 AND 4 THEN '1-4'
    WHEN ha.los BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  CASE
    WHEN ha.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
    WHEN ha.admission_type = 'ELECTIVE' THEN 'Elective'
  END AS adm_stratum,
  AVG(IFNULL(dc.num_diag, 0)) AS mean_noninvasive_diagnostics_per_admission
FROM
  hf_admissions ha
  LEFT JOIN diagnostic_counts dc
    ON ha.hadm_id = dc.hadm_id
GROUP BY
  los_group,
  adm_stratum
ORDER BY
  los_group,
  adm_stratum;
WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'With ICU' ELSE 'Without ICU' END AS icu_stratum
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) i
    ON adm.hadm_id = i.hadm_id
  WHERE pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 40 AND 50
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code = '436'))
        OR (icd_version = 10 AND icd_code LIKE 'I63%')
    )
),

imaging_events AS (
  -- HCPCS imaging events
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    WHERE d.code = h.hcpcs_cd
      AND REGEXP_CONTAINS(LOWER(d.long_description), r'(ct|mri|ultrasound|angiography|x-ray|radiology|scan)')
  )
  UNION ALL
  -- ICD procedure imaging events
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    WHERE d.icd_code = p.icd_code 
      AND d.icd_version = p.icd_version
      AND REGEXP_CONTAINS(LOWER(d.long_title), r'(ct|mri|ultrasound|angiography|x-ray|radiology|scan)')
  )
),

imaging_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_imaging
  FROM imaging_events
  GROUP BY hadm_id
)

SELECT 
  CASE 
    WHEN c.los_days <= 4 THEN '1-4 days' 
    ELSE '5-7 days' 
  END AS stay_length_group,
  c.icu_stratum,
  AVG(COALESCE(i.num_imaging, 0)) AS mean_imaging_procedures,
  MIN(COALESCE(i.num_imaging, 0)) AS min_imaging_procedures,
  MAX(COALESCE(i.num_imaging, 0)) AS max_imaging_procedures
FROM cohort c
LEFT JOIN imaging_counts i 
  ON c.hadm_id = i.hadm_id
GROUP BY 
  stay_length_group, 
  c.icu_stratum
ORDER BY 
  stay_length_group, 
  c.icu_stratum;
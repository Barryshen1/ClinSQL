WITH hf_admissions AS (
  SELECT 
    d.hadm_id,
    CASE 
      WHEN MAX(CASE WHEN d.seq_num = 1 AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%') THEN 1 ELSE 0 END) = 1 THEN 'primary'
      WHEN MAX(CASE WHEN d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%' THEN 1 ELSE 0 END) = 1 THEN 'secondary'
    END AS hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%')
  GROUP BY d.hadm_id
),

los_groups AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN hf_admissions hf ON a.hadm_id = hf.hadm_id
  WHERE DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

imaging_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS imaging_count
  FROM (
    SELECT ce.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE di.linksto = 'chartevents'
      AND (LOWER(di.label) LIKE '%ct%'
        OR LOWER(di.label) LIKE '%mri%'
        OR LOWER(di.label) LIKE '%xray%'
        OR LOWER(di.label) LIKE '%x-ray%'
        OR LOWER(di.label) LIKE '%ultrasound%'
        OR LOWER(di.label) LIKE '%echo%'
        OR LOWER(di.label) LIKE '%rad%'
        OR LOWER(di.label) LIKE '%imaging%'
        OR LOWER(di.label) LIKE '%scan%'
        OR LOWER(di.label) LIKE '%fluoro%'
        OR LOWER(di.label) LIKE '%angi%'
        OR LOWER(di.label) LIKE '%nuclear%')
    
    UNION ALL
    
    SELECT pe.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    WHERE di.linksto = 'procedureevents'
      AND (LOWER(di.label) LIKE '%ct%'
        OR LOWER(di.label) LIKE '%mri%'
        OR LOWER(di.label) LIKE '%xray%'
        OR LOWER(di.label) LIKE '%x-ray%'
        OR LOWER(di.label) LIKE '%ultrasound%'
        OR LOWER(di.label) LIKE '%echo%'
        OR LOWER(di.label) LIKE '%rad%'
        OR LOWER(di.label) LIKE '%imaging%'
        OR LOWER(di.label) LIKE '%scan%'
        OR LOWER(di.label) LIKE '%fluoro%'
        OR LOWER(di.label) LIKE '%angi%'
        OR LOWER(di.label) LIKE '%nuclear%')
  ) combined_imaging
  GROUP BY hadm_id
)

SELECT 
  lg.los_group,
  ha.hf_type,
  PERCENTILE_CONT(im.imaging_count, 0.25) AS p25,
  PERCENTILE_CONT(im.imaging_count, 0.5) AS p50,
  PERCENTILE_CONT(im.imaging_count, 0.75) AS p75
FROM los_groups lg
INNER JOIN hf_admissions ha ON lg.hadm_id = ha.hadm_id
LEFT JOIN imaging_counts im ON lg.hadm_id = im.hadm_id
WHERE lg.los_group IS NOT NULL
  AND ha.hf_type IS NOT NULL
GROUP BY lg.los_group, ha.hf_type
ORDER BY lg.los_group, ha.hf_type;
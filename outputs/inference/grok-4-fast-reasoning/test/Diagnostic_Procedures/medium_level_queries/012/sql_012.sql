WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_bin
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = '9' AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
          OR
          (d.icd_version = '10' AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%'))
        )
    )
    AND los_days BETWEEN 1 AND 7
)
SELECT 
  los_bin,
  COUNT(DISTINCT hadm_id) AS patient_counts,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM (
  SELECT 
    qa.*,
    (SELECT COUNT(*)
     FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
       ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
     WHERE 
       pi.subject_id = qa.subject_id
       AND pi.hadm_id = qa.hadm_id
       AND (
         LOWER(dip.long_title) LIKE '%ultrasound%'
         OR LOWER(dip.long_title) LIKE '%echocardiography%'
         OR LOWER(dip.long_title) LIKE '%echo%'
       )
    ) AS ultrasound_count
  FROM qualifying_admissions qa
)
GROUP BY los_bin
ORDER BY 
  CASE los_bin 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;
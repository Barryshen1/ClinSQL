WITH aki_admissions AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    CASE 
      WHEN MAX(CASE WHEN d.seq_num = 1 AND d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS aki_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10 AND d.icd_code LIKE 'N17%'
  GROUP BY d.subject_id, d.hadm_id
),
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN aki_admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
),
los_data AS (
  SELECT 
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered pf ON a.hadm_id = pf.hadm_id
),
ct_mri_counts AS (
  SELECT 
    hadm_id,
    COALESCE(SUM(hosp_count), 0) + COALESCE(SUM(icu_count), 0) AS total_ct_mri
  FROM (
    SELECT 
      p.hadm_id,
      COUNT(*) AS hosp_count,
      NULL AS icu_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%CT%' OR d.long_title LIKE '%MRI%'
    GROUP BY p.hadm_id
    UNION ALL
    SELECT 
      pe.hadm_id,
      NULL AS hosp_count,
      COUNT(*) AS icu_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON pe.itemid = di.itemid
    WHERE di.label LIKE '%CT%' OR di.label LIKE '%MRI%'
    GROUP BY pe.hadm_id
  ) combined
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN los.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los.los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  aki.aki_type,
  COUNT(DISTINCT los.hadm_id) AS patient_count,
  AVG(ctm.total_ct_mri) AS mean_ct_mri
FROM los_data los
JOIN aki_admissions aki ON los.hadm_id = aki.hadm_id
JOIN ct_mri_counts ctm ON los.hadm_id = ctm.hadm_id
WHERE los.los_days BETWEEN 1 AND 7
GROUP BY los_group, aki.aki_type;
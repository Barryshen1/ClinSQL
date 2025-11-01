WITH los_bins AS (
  SELECT 
    CAST(adm.subject_id AS STRING) AS subject_id_str,
    CAST(adm.hadm_id AS STRING) AS hadm_id_str,
    pat.gender,
    pat.anchor_age,
    EXTRACT(DAY FROM (DATE(adm.dischtime) - DATE(adm.admittime))) AS los_days,
    CASE 
      WHEN EXTRACT(DAY FROM (DATE(adm.dischtime) - DATE(adm.admittime))) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN EXTRACT(DAY FROM (DATE(adm.dischtime) - DATE(adm.admittime))) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON CAST(adm.subject_id AS STRING) = CAST(pat.subject_id AS STRING)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON CAST(adm.subject_id AS STRING) = CAST(diag.subject_id AS STRING)
    AND CAST(adm.hadm_id AS STRING) = CAST(diag.hadm_id AS STRING)
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND diag.icd_version = '10'
    AND diag.seq_num = 1
    AND STARTS_WITH(CAST(diag.icd_code AS STRING), 'I21')
    AND adm.hospital_expire_flag = 0
    AND EXTRACT(DAY FROM (DATE(adm.dischtime) - DATE(adm.admittime))) BETWEEN 1 AND 7
),
ultrasound_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (label LIKE '%Echo%' OR label LIKE '%Echocardiography%' OR label LIKE '%Echocardiogram%' 
         OR label LIKE '%Ultrasound%' OR label LIKE '%Cardiac%')
    AND category IN ('Imaging', 'Echo')
),
echo_counts AS (
  SELECT 
    los.subject_id_str,
    los.hadm_id_str,
    los.los_group,
    COUNT(CASE WHEN lev.itemid IN (SELECT itemid FROM ultrasound_itemids) 
               AND lev.valuenum IS NOT NULL 
               AND lev.charttime >= DATE(adm.admittime) 
               AND lev.charttime <= DATE(adm.dischtime) THEN 1 END) AS num_ultrasounds
  FROM los_bins los
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON los.hadm_id_str = CAST(adm.hadm_id AS STRING)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lev
    ON los.subject_id_str = CAST(lev.subject_id AS STRING)
    AND los.hadm_id_str = CAST(lev.hadm_id AS STRING)
  GROUP BY los.subject_id_str, los.hadm_id_str, los.los_group
)
SELECT 
  los_group,
  COUNT(DISTINCT hadm_id_str) AS admission_count,
  AVG(num_ultrasounds) AS mean_ultrasounds_per_admission
FROM echo_counts
WHERE los_group != 'Other'
GROUP BY los_group
ORDER BY 
  CASE los_group 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;
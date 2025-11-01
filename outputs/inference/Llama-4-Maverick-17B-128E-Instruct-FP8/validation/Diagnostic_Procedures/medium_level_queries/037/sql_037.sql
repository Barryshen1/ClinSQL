WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 43 AND 53
),
admissions_ami AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
         CASE WHEN d.seq_num = (SELECT MIN(seq_num) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE hadm_id = a.hadm_id AND icd_version = 9 AND icd_code LIKE '410%') THEN 'Primary'
              ELSE 'Secondary' END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.icd_version = 9 AND d.icd_code LIKE '410%' AND a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
),
length_of_stay AS (
  SELECT hadm_id, ami_type, DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM admissions_ami
),
radiography_ct AS (
  SELECT h.hadm_id, COUNT(*) AS num_radiography_ct
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE dh.short_description LIKE '%Radiography%' OR dh.short_description LIKE '%CT%'
  GROUP BY h.hadm_id
)
SELECT 
  aa.ami_type,
  CASE WHEN los.los BETWEEN 1 AND 3 THEN '1-3 days'
       WHEN los.los BETWEEN 4 AND 7 THEN '4-7 days'
       ELSE 'Outside range' END AS los_category,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(rc.num_radiography_ct, 100)[OFFSET(50)] AS median_radiography_ct,
  APPROX_QUANTILES(rc.num_radiography_ct, 100)[OFFSET(25)] AS iqr_lower_radiography_ct,
  APPROX_QUANTILES(rc.num_radiography_ct, 100)[OFFSET(75)] AS iqr_upper_radiography_ct
FROM admissions_ami aa
JOIN length_of_stay los ON aa.hadm_id = los.hadm_id
LEFT JOIN radiography_ct rc ON aa.hadm_id = rc.hadm_id
WHERE los.los BETWEEN 1 AND 7
GROUP BY aa.ami_type, los_category
ORDER BY aa.ami_type, los_category;
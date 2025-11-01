WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_type,
    TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  CROSS JOIN UNNEST([DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR)]) AS birth_date
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd 
    ON a.subject_id = d_icd.subject_id AND a.hadm_id = d_icd.hadm_id AND d_icd.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'Emergency'
    AND (LOWER(d.long_title) LIKE '%urinary tract infection%' OR LOWER(d.long_title) LIKE '%uti%')
    AND TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) BETWEEN 60 AND 70
),
next_adm AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
index_adms_with_readmission AS (
  SELECT 
    i.*,
    TIMESTAMP_DIFF(i.dischtime, i.admittime, DAY) AS los,
    CASE 
      WHEN n.next_admit IS NOT NULL AND n.next_admit <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS readmitted
  FROM index_adms i
  LEFT JOIN next_adm n 
    ON i.subject_id = n.subject_id AND i.hadm_id = n.hadm_id
),
readmission_rate AS (
  SELECT 
    (SELECT COUNT(*) FROM index_adms_with_readmission WHERE readmitted = 1) * 100.0 / 
    NULLIF((SELECT COUNT(*) FROM index_adms_with_readmission), 0) AS rate
),
stats AS (
  SELECT 
    readmitted,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    (SUM(IF(los > 9, 1, 0)) * 100.0 / COUNT(*)) AS percent_los_gt9
  FROM index_adms_with_readmission
  GROUP BY readmitted
)
SELECT 
  r.rate AS readmission_rate,
  s.readmitted,
  s.median_los,
  s.percent_los_gt9
FROM stats s, readmission_rate r;
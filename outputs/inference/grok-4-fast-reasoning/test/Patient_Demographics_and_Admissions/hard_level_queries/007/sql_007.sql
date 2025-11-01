WITH index_adms AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    a.dischtime,
    a.admittime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = a.subject_id 
        AND a2.hadm_id != a.hadm_id 
        AND a2.admittime > a.dischtime 
        AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code = '4359') 
      OR (d.icd_version = 10 AND d.icd_code = 'G459')
    )
)
SELECT 
  ROUND(AVG(CAST(readmitted AS INT64)) * 100, 2) AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM index_adms WHERE readmitted) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM index_adms WHERE NOT readmitted) AS median_los_nonreadmitted_days,
  ROUND(AVG(CASE WHEN los > 10 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_index_stays_gt10_days
FROM index_adms;
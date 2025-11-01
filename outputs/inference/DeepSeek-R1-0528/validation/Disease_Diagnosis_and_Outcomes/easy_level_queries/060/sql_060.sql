WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code IN (
        '5310','5312','5314','5316','5320','5322','5324','5326',
        '5330','5332','5334','5336','5340','5342','5344','5346',
        '5780','5781','5789'
      )) 
      OR 
      (d.icd_version = 10 AND d.icd_code IN (
        'K250','K252','K254','K256','K260','K262','K264','K266',
        'K270','K272','K274','K276','K280','K282','K284','K286',
        'K920','K921','K922'
      ))
    )
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 74 AND 84
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM cohort;
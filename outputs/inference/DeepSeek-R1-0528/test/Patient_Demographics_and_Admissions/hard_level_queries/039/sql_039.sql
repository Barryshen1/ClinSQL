WITH index_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_index
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code = '51881') OR  -- ICD-9
      (d.icd_version = 10 AND d.icd_code IN (
        'J9600','J9601','J9602','J9620','J9621','J9622','J9690','J9691','J9692'  -- ICD-10
      ))
    )
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 65 AND 75
),

index_with_readmit AS (
  SELECT 
    *,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` r 
      WHERE 
        r.subject_id = i.subject_id 
        AND r.hadm_id != i.hadm_id 
        AND r.admittime > i.dischtime 
        AND r.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM index_admissions i
)

SELECT 
  '30_day_readmission_rate' AS metric,
  ROUND(AVG(IF(readmitted_30d, 1, 0)) * 100, 2) AS value  -- Fixed: Replaced invalid cast
FROM index_with_readmit
UNION ALL
SELECT 
  'median_los_readmitted' AS metric,
  ROUND(APPROX_QUANTILES(los_index, 2)[OFFSET(1)], 2) AS value
FROM index_with_readmit
WHERE readmitted_30d
UNION ALL
SELECT 
  'median_los_non_readmitted' AS metric,
  ROUND(APPROX_QUANTILES(los_index, 2)[OFFSET(1)], 2) AS value
FROM index_with_readmit
WHERE NOT readmitted_30d
UNION ALL
SELECT 
  'percent_los_gt_9_days' AS metric,
  ROUND(AVG(IF(los_index > 9, 1, 0)) * 100, 2) AS value
FROM index_with_readmit;
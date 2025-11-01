WITH patients_female_old AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
admissions_with_los AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_female_old p ON a.subject_id = p.subject_id
  WHERE a.dischtime > a.admittime
),
asthma_adms AS (
  SELECT DISTINCT
    awl.subject_id,
    awl.hadm_id,
    awl.los_days
  FROM admissions_with_los awl
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = awl.subject_id
      AND d.hadm_id = awl.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '493%')
        OR
        (d.icd_version = 10 AND (d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%'))
      )
  )
  AND awl.los_days BETWEEN 1 AND 7
),
procedures_count AS (
  SELECT 
    aa.hadm_id,
    aa.los_days,
    COUNT(p.seq_num) AS num_procedures,
    CASE 
      WHEN aa.los_days <= 3 THEN '1-3'
      ELSE '4-7'
    END AS los_group
  FROM asthma_adms aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON p.hadm_id = aa.hadm_id
  GROUP BY aa.hadm_id, aa.los_days
)
SELECT 
  los_group,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS p75
FROM procedures_count
GROUP BY los_group
ORDER BY 
  CASE los_group WHEN '1-3' THEN 1 ELSE 2 END;
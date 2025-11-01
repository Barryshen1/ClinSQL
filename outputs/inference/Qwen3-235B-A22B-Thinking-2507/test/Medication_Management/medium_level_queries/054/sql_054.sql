WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 56 AND 66
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
drug_use AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN e.charttime >= c.admittime AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS first_48h,
    MAX(CASE WHEN e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND e.charttime <= c.dischtime THEN 1 ELSE 0 END) AS last_24h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND (
      LOWER(e.medication) LIKE '%exenatide%' OR
      LOWER(e.medication) LIKE '%liraglutide%' OR
      LOWER(e.medication) LIKE '%dulaglutide%' OR
      LOWER(e.medication) LIKE '%semaglutide%' OR
      LOWER(e.medication) LIKE '%lixisenatide%' OR
      LOWER(e.medication) LIKE '%albiglutide%' OR
      LOWER(e.medication) LIKE '%byetta%' OR
      LOWER(e.medication) LIKE '%bydureon%' OR
      LOWER(e.medication) LIKE '%victoza%' OR
      LOWER(e.medication) LIKE '%saxenda%' OR
      LOWER(e.medication) LIKE '%trulicity%' OR
      LOWER(e.medication) LIKE '%ozempic%' OR
      LOWER(e.medication) LIKE '%rybelsus%' OR
      LOWER(e.medication) LIKE '%lyxumia%' OR
      LOWER(e.medication) LIKE '%tanzeum%'
    )
  GROUP BY c.hadm_id
)
SELECT 
  (SUM(first_48h) * 100.0 / COUNT(*)) AS prevalence_first_48h,
  (SUM(last_24h) * 100.0 / COUNT(*)) AS prevalence_last_24h,
  ((SUM(last_24h) * 100.0 / COUNT(*)) - (SUM(first_48h) * 100.0 / COUNT(*))) AS net_change
FROM drug_use;
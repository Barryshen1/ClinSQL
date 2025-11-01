WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
    )
),
medication_complexity AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CONCAT(p.drug, '||', p.route)) AS drug_route_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR
  GROUP BY c.hadm_id
),
readmission AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
    AND a2.admittime >= c.dischtime
    AND a2.admittime <= c.dischtime + INTERVAL 30 DAY
    AND a2.hadm_id != c.hadm_id
  GROUP BY c.hadm_id
),
combined AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    mc.drug_route_count,
    NTILE(4) OVER (ORDER BY mc.drug_route_count) AS quartile
  FROM cohort c
  JOIN medication_complexity mc
    ON c.hadm_id = mc.hadm_id
)
SELECT
  quartile,
  COUNT(*) AS admissions,
  MIN(drug_route_count) AS min_score,
  MAX(drug_route_count) AS max_score,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(r.readmitted_30d) * 100 AS readmission_30d_pct
FROM combined
LEFT JOIN readmission r
  ON combined.hadm_id = r.hadm_id
GROUP BY quartile
ORDER BY quartile;
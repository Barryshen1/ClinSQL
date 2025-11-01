WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
),
medication_counts AS (
  SELECT
    f.hadm_id,
    COUNT(DISTINCT p.drug) AS med_count
  FROM filtered_admissions f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON f.hadm_id = p.hadm_id
  GROUP BY f.hadm_id
),
quintiles AS (
  SELECT
    f.hadm_id,
    f.subject_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    m.med_count,
    NTILE(5) OVER (ORDER BY m.med_count) AS quintile,
    DATE_DIFF(f.dischtime, f.admittime, DAY) AS los,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = f.subject_id
        AND a2.admittime > f.dischtime
        AND a2.admittime <= DATE_ADD(f.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p1
      WHERE p1.hadm_id = f.hadm_id
        AND p1.drug IN ('warfarin', 'heparin', 'enoxaparin', 'apixaban', 'rivaroxaban', 'dabigatran', 'edoxaban')
    ) AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p2
      WHERE p2.hadm_id = f.hadm_id
        AND p2.drug IN ('morphine', 'fentanyl', 'oxycodone', 'hydromorphone', 'codeine', 'hydrocodone', 'meperidine', 'methadone', 'buprenorphine')
    ) THEN 1 ELSE 0 END AS coadmin
  FROM filtered_admissions f
  JOIN medication_counts m ON f.hadm_id = m.hadm_id
)
SELECT
  quintile,
  AVG(los) AS avg_los,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_pct,
  SUM(readmitted_30d) * 100.0 / COUNT(*) AS readmission_30d_pct,
  SUM(coadmin) AS coadministration_count
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
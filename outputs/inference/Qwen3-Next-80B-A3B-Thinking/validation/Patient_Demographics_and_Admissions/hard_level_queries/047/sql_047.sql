WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE 'EMERGENCY%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
readmitted_flag AS (
  SELECT
    ia.hadm_id,
    ia.los,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
        AND a2.hadm_id != ia.hadm_id
    ) THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions ia
)
SELECT
  SUM(readmitted) / COUNT(*) AS readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 1 THEN los ELSE NULL END) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 0 THEN los ELSE NULL END) AS median_los_non_readmitted,
  SUM(CASE WHEN los > 4 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS los_gt4_pct
FROM readmitted_flag;
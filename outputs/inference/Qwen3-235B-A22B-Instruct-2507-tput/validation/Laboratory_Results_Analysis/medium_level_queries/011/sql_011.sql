WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
    AND LOWER(d.long_title) LIKE '%chest pain%'
),
hs_tnt_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  JOIN chest_pain_admissions cpa ON le.hadm_id = cpa.hadm_id
  WHERE LOWER(dl.label) LIKE '%troponin%t%' 
    AND le.charttime >= cpa.admittime
    AND le.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    CASE
      WHEN valuenum <= 14 THEN 'normal'
      WHEN valuenum BETWEEN 15 AND 59 THEN 'borderline'
      WHEN valuenum >= 60 THEN 'myocardial injury'
      ELSE 'unknown'
    END AS category
  FROM hs_tnt_first
  WHERE rn = 1
),
counts AS (
  SELECT
    category,
    COUNT(*) AS n
  FROM categorized
  GROUP BY category
),
total AS (
  SELECT SUM(n) AS total_n FROM counts
)
SELECT
  c.category,
  ROUND(100.0 * c.n / t.total_n, 2) AS percent_distribution
FROM counts c
CROSS JOIN total t
ORDER BY c.category;
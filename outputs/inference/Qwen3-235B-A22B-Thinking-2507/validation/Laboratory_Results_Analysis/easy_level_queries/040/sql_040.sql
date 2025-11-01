WITH dka_admissions AS (
  SELECT 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11')
    )
),
glucose_peaks AS (
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_glucose
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN
    dka_admissions da
    ON le.hadm_id = da.hadm_id
  WHERE
    le.itemid IN (50809, 50931)  -- Serum glucose item IDs
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_glucose, 100)[OFFSET(50)] AS median_peak_glucose
FROM
  glucose_peaks;
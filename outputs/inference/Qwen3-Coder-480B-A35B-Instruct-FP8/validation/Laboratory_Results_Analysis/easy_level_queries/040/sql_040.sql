WITH dka_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('2501', '25010', '25011', '25012', '25013'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('E101', 'E111', 'E121', 'E131', 'E141'))
    )
),
peak_glucose_per_admission AS (
  SELECT
    l.hadm_id,
    MAX(l.valuenum) AS peak_glucose
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    dka_admissions dka
    ON l.hadm_id = dka.hadm_id
  WHERE
    LOWER(d.label) LIKE '%glucose%'
    AND d.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND l.charttime BETWEEN dka.admittime AND dka.dischtime
  GROUP BY
    l.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_glucose, 2)[OFFSET(1)] AS median_peak_serum_glucose
FROM
  peak_glucose_per_admission;
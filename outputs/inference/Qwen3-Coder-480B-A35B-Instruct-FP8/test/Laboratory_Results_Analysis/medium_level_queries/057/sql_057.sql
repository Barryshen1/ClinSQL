WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
acs_admissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('410', '4100', '4101', '4102', '4103', '4104', '4105', '4106', '4107', '4108', '4109', '4111', '4139'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('I20', 'I21', 'I22', 'I23', 'I24'))
    )
)
SELECT
  CASE
    WHEN t.troponin_value <= 0.04 THEN 'Normal (≤0.04)'
    WHEN t.troponin_value > 0.04 AND t.troponin_value <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN t.troponin_value > 0.1 THEN 'Elevated (>0.1)'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM
  troponin_first AS t
INNER JOIN
  acs_admissions AS a
  ON t.hadm_id = a.hadm_id
WHERE
  t.rn = 1
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
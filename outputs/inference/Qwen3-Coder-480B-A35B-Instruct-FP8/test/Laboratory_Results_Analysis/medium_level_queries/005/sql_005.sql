WITH primary_diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      dd.icd_code LIKE 'I21%' OR
      dd.icd_code LIKE '410%' OR
      dd.icd_code IN ('R07.9', '786.59')
    )
),
eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
),
admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    primary_diagnosis pd ON a.hadm_id = pd.hadm_id
  JOIN
    eligible_patients ep ON a.subject_id = ep.subject_id
),
troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.flag,
    l.ref_range_lower,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    admissions a
    ON l.hadm_id = a.hadm_id
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.label) LIKE '%high sensitive%'
    AND l.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN f.valuenum <= f.ref_range_upper THEN 'Normal'
    WHEN f.valuenum > f.ref_range_upper AND f.valuenum <= 3 * f.ref_range_upper THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS troponin_category,
  COUNT(*) AS count
FROM
  troponin_first f
WHERE
  f.rn = 1
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
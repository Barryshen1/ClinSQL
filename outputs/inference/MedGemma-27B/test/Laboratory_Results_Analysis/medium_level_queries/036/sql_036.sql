WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'M' AND anchor_age BETWEEN 77 AND 87
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.long_title AS diagnosis
  FROM admissions AS a
  INNER JOIN diagnoses_icd AS di
    ON a.hadm_id = di.hadm_id
  INNER JOIN d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1 -- Assuming the first diagnosis is the primary one
    AND d.long_title LIKE '%AMI%' -- AMI diagnosis
), TnTInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.value AS tnt_value,
    l.valueuom AS tnt_uom,
    l.ref_range_lower,
    l.ref_range_upper
  FROM labevents AS l
  INNER JOIN d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin I' -- Assuming Troponin I is hs-TnT
    AND l.valueuom = 'ng/L' -- Assuming ng/L is the unit for hs-TnT
)
SELECT
  CASE
    WHEN tnt.ref_range_lower IS NULL OR tnt.ref_range_upper IS NULL THEN 'Unknown'
    WHEN tnt.valuenum < tnt.ref_range_lower THEN 'Myocardial injury'
    WHEN tnt.valuenum >= tnt.ref_range_lower AND tnt.valuenum <= tnt.ref_range_upper THEN 'Normal'
    ELSE 'Borderline'
  END AS tnt_category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage
FROM TnTInfo AS tnt
INNER JOIN AdmissionInfo AS ai
  ON tnt.subject_id = ai.subject_id AND tnt.hadm_id = ai.hadm_id
INNER JOIN PatientInfo AS pi
  ON tnt.subject_id = pi.subject_id
WHERE
  tnt.charttime = (
    SELECT
      MIN(charttime)
    FROM labevents AS l2
    WHERE
      l2.subject_id = tnt.subject_id AND l2.hadm_id = tnt.hadm_id AND l2.itemid = tnt.itemid
  ) -- Get the initial TnT value
GROUP BY
  tnt_category
ORDER BY
  tnt_category;
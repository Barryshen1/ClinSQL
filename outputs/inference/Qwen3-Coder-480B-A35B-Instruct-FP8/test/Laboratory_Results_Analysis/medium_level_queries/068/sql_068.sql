SELECT
  CASE
    WHEN le.valuenum < 0.014 THEN 'Normal'
    WHEN le.valuenum >= 0.014 AND le.valuenum < 0.04 THEN 'Borderline'
    WHEN le.valuenum >= 0.04 THEN 'Myocardial Injury'
  END AS troponin_category,
  COUNT(DISTINCT p.subject_id) AS patient_count
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents le
  ON p.subject_id = le.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems d
  ON le.itemid = d.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 42 AND 52
  AND LOWER(d.label) LIKE '%troponin t%'
  AND le.valuenum IS NOT NULL
  AND le.valueuom = 'ng/mL'
GROUP BY
  troponin_category
ORDER BY
  troponin_category;
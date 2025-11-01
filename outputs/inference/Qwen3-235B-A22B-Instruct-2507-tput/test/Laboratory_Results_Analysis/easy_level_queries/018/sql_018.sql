WITH female_icu AS (
  SELECT p.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
),
ph_labs AS (
  SELECT fi.stay_id, l.valuenum, l.charttime, fi.intime,
         ROW_NUMBER() OVER (PARTITION BY fi.stay_id ORDER BY l.charttime) AS rn
  FROM female_icu fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON fi.subject_id = l.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d
    ON l.itemid = d.itemid
  WHERE d.label = 'pH'
    AND d.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= fi.intime
    AND l.charttime <= fi.intime + INTERVAL '6' HOUR
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_ph_on_icu_admission
FROM ph_labs
WHERE rn = 1;
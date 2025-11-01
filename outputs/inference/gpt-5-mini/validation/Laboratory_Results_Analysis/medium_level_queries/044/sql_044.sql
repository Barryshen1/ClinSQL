WITH troponin_t_first AS (
  -- Earliest Troponin‑T lab per hospital admission (hadm_id)
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime, l.labevent_id) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE
    -- match common label variants for Troponin-T (case-insensitive)
    (LOWER(li.label) LIKE '%troponin t%' OR LOWER(li.label) LIKE '%troponin-t%')
    -- require a numeric value
    AND l.valuenum IS NOT NULL
    -- require units that include "ng" (e.g., "ng/mL")
    AND LOWER(COALESCE(l.valueuom, '')) LIKE '%ng%'
),
first_troponin_per_adm AS (
  -- keep only the first troponin measurement per admission
  SELECT subject_id, hadm_id, valuenum, valueuom
  FROM troponin_t_first
  WHERE rn = 1
)
SELECT
  COUNT(*) AS n,
  AVG(valuenum) AS mean,
  STDDEV_SAMP(valuenum) AS sd,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max,
  -- median and quartiles via APPROX_QUANTILES (100 buckets -> use offsets 25,50,75)
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
FROM first_troponin_per_adm ft
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON ft.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ft.subject_id = p.subject_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 54 AND 64
  -- initial Troponin-T greater than 0.01 ng/mL
  AND ft.valuenum > 0.01;
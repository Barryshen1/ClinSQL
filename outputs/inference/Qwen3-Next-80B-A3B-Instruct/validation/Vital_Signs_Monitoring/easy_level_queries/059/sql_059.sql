WITH first_spo2 AS (
  SELECT 
    c.hadm_id,
    c.valuenum AS spo2_value,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY c.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON c.stay_id = i.stay_id
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE 
    d.label IN ('SpO2', 'O2 Saturation', 'O2 Sat', 'O2 Sat (%)', 'SpO2 (%)')
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 0 AND 100
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
)
SELECT 
  STDDEV(spo2_value) AS std_dev_first_spo2
FROM first_spo2
WHERE rn = 1;
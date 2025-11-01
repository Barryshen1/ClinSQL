with a full SELECT and closing parenthesis.
3. Fix the `vital_events` CTE to reference `chartevents` (not `chart`).
4. Use correct dataset prefixes: `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu`.
5. Join `chartevents` with `d_items` to identify HR, MAP, RR.
6. Filter vital signs to the first 48 hours of ICU stay (`charttime` between `intime` and `intime + 48 hours`).
7. Define the "vital instability index" as the count of abnormal vital signs in the first 48h:
   - Tachycardia: HR > 100
   - Hypotension: MAP < 65
   - Tachypnea: RR > 20
8. Compute the 95th percentile of this index among UGIB patients.
9. Identify the top decile (90th percentile) of UGIB patients.
10. Compare top decile UGIB patients vs. controls on:
    - Proportion with tachycardia (>100) in first 48h
    - Proportion with MAP < 65 in first 48h
    - Proportion with tachypnea (>20) in first 48h
    - Median ICU LOS
    - Mortality rate (hospital_expire_flag)

We'll structure the query with 7 CTEs:
- `ugib_patients`: UGIB cohort (60–70, male)
- `control_patients`: Non-UGIB cohort (same age/gender, no UGIB diagnosis)
- `vital_events`: HR, MAP, RR in first 48h for both cohorts
- `instability_index`: Count of abnormal vitals per stay
- `percentiles`: Compute 95th and 90th percentiles for UGIB
- `top_decile_ugib`: UGIB patients in top 10% of instability index
- `final_comparison`: Aggregate comparison metrics

We use `PERCENTILE_CONT(0.95)` and `PERCENTILE_CONT(0.90)` for percentiles.

Note: We assume "vital instability index" = count of abnormal vital signs (HR>100, MAP<65, RR>20) in first 48h.

We use `d_items` to map `itemid` to labels: 'Heart Rate', 'MAP', 'Respiratory Rate'.

We use `COUNTIF` to compute proportions of abnormal vitals and `AVG` for mortality.

We ensure all table references use correct dataset prefixes.

sql
WITH ugid_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, i.stay_id, i.intime, i.outtime, a.hadm_id, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
    AND (
      LOWER(did.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(did.long_title) LIKE '%upper gi bleed%'
      OR LOWER(did.long_title) LIKE '%hematemesis%'
      OR LOWER(did.long_title) LIKE '%melena%'
      OR LOWER(did.long_title) LIKE '%upper gastrointestinal bleeding%'
      OR LOWER(did.long_title) LIKE '%digestive tract hemorrhage%'
      OR d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K92.0', 'K92.1', 'K92.2', '578.9', '530.7', '531.0', '531.1', '531.2', '531.3', '531.4', '531.5', '531.6', '531.7', '531.8', '531.9', '532.0', '532.1', '532.2', '532.3', '532.4', '532.5', '532.6', '532.7', '532.8', '532.9', '533.0', '533.1', '533.2', '533.3', '533.4', '533.5', '533.6', '533.7', '533.8', '533.9', '534.0', '534.1', '534.2', '534.3', '534.4', '534.5', '534.6', '534.7', '534.8', '534.9')
    )
),

control_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, i.stay_id, i.intime, i.outtime, a.hadm_id, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = i.hadm_id
        AND (
          LOWER(did.long_title) LIKE '%gastrointestinal hemorrhage%'
          OR LOWER(did.long_title) LIKE '%upper gi bleed%'
          OR LOWER(did.long_title) LIKE '%hematemesis%'
          OR LOWER(did.long_title) LIKE '%melena%'
          OR LOWER(did.long_title) LIKE '%upper gastrointestinal bleeding%'
          OR LOWER(did.long_title) LIKE '%digestive tract hemorrhage%'
          OR d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K92.0', 'K92.1', 'K92.2', '578.9', '530.7', '531.0', '531.1', '531.2', '531.3', '531.4', '531.5', '531.6', '531.7', '531.8', '531.9', '532.0', '532.1', '532.2', '532.3', '532.4', '532.5', '532.6', '532.7', '532.8', '532.9', '533.0', '533.1', '533.2', '533.3', '533.4', '533.5', '533.6;